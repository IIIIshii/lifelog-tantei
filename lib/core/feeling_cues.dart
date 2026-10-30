// 聴取の会話から読み取った「感じ方の手がかり」を扱う純粋関数群。
//
// 好きなことや苦手なことは、点数や選択肢で答えさせると記録が続かない。
// 一方、会話にはすでに出ている（「気づいたら1時間たってた」「資料作りは後回しにした」）。
// AI がそれを出来事ごとに読み取り、根拠の発言といっしょに残す。
// 読み違いを貯めないよう、ここで「根拠が本当に依頼人の発言にあるか」を確かめる。
import 'auto_fill.dart';

/// 感じ方の種類。後から集計できるよう、自由な文ではなく決まった語に限る。
enum Feeling {
  enjoyed('楽しそう'),
  absorbed('時間を忘れた'),
  proud('嬉しい・誇らしい'),
  tired('疲れた'),
  avoided('後回しにした'),
  bored('退屈だった'),
  anxious('不安・緊張した');

  const Feeling(this.label);

  final String label;

  /// 保存に使うキー。enum の名前をそのまま使う。
  String get key => name;

  static Feeling? fromKey(Object? key) {
    for (final feeling in values) {
      if (feeling.name == key) return feeling;
    }
    return null;
  }
}

/// 1日に残す手がかりの上限。多いほど、こじつけが混ざりやすくなる。
const int kMaxFeelingCuesPerDay = 5;

/// 出来事名の最大文字数。
const int kMaxActivityLength = 30;

/// 感じ方の手がかり1件。
class FeelingCue {
  const FeelingCue({
    required this.activity,
    required this.feeling,
    required this.quote,
  });

  /// どの出来事についての感じ方か（例: 「資料作り」）。
  final String activity;

  final Feeling feeling;

  /// 根拠にした依頼人の発言（そのままの引用）。
  final String quote;

  Map<String, dynamic> toMap() => {
    'activity': activity,
    'feeling': feeling.key,
    'quote': quote,
  };

  static FeelingCue? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final feeling = Feeling.fromKey(raw['feeling']);
    final activity = raw['activity'];
    final quote = raw['quote'];
    if (feeling == null || activity is! String || quote is! String) return null;
    if (activity.trim().isEmpty || quote.trim().isEmpty) return null;
    return FeelingCue(
      activity: activity.trim(),
      feeling: feeling,
      quote: quote.trim(),
    );
  }
}

// 空白と改行の違いで、引用が一致しなくなるのを防ぐ。
String _squash(String text) => text.replaceAll(RegExp(r'\s+'), '');

/// AI の応答から、残してよい手がかりだけを取り出す。
///
/// 捨てるもの:
/// - 感じ方の種類が決まった語にないもの
/// - 根拠の引用が、依頼人の発言のどこにも無いもの（AI が発言を作った場合）。
///   探偵の質問の引用も、依頼人の発言ではないので捨てる
/// - 出来事名が空のもの
/// 同じ出来事・同じ感じ方の重複は1件にし、[kMaxFeelingCuesPerDay] 件までにする。
List<FeelingCue> feelingCuesFromExtraction(
  Object? raw,
  Iterable<TalkLine> lines,
) {
  if (raw is! List) return const [];
  final userTalk = [
    for (final line in lines)
      if (line.role == 'user' && line.text.trim().isNotEmpty)
        _squash(line.text),
  ];
  final cues = <FeelingCue>[];
  final seen = <String>{};
  for (final item in raw) {
    final cue = FeelingCue.fromMap(item);
    if (cue == null) continue;
    final quote = _squash(cue.quote);
    if (!userTalk.any((talk) => talk.contains(quote))) continue;
    final activity = cue.activity.length > kMaxActivityLength
        ? cue.activity.substring(0, kMaxActivityLength)
        : cue.activity;
    if (!seen.add('$activity/${cue.feeling.key}')) continue;
    cues.add(
      FeelingCue(activity: activity, feeling: cue.feeling, quote: cue.quote),
    );
    if (cues.length >= kMaxFeelingCuesPerDay) break;
  }
  return cues;
}
