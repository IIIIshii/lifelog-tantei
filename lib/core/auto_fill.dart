// 聴取の会話から、記録の表を自動で埋めるための純粋関数群。
//
// 同じ事実（睡眠時間、運動したか、午前にしたこと）を、聴取で話したあとに
// 表でもう一度入れさせると二度手間になる。AI が先に埋め、利用者は違うところだけ直す。
// 一方、自動で入れた値が間違っていると記録への信頼が下がるので、
// 次の3つを守る。ここでは、画面や Firestore に依存しない判断だけを持つ。
//
// 1. すでに入っている値は上書きしない（利用者の入力が常に優先）
// 2. 自動で入れた項目の id を記録に残し、利用者の入力と区別する
// 3. 何を入れたかを、利用者が見られる文にする
import 'daily_record.dart';

/// 記録ドキュメントのうち、AI が会話から自動で入れた項目の id を並べるキー。
const String kAutoFilledKey = 'autoFilled';

/// 会話の1行。role は 'ai'（探偵）か 'user'（依頼人）。それ以外の行は読み取りに使わない。
typedef TalkLine = ({String role, String text});

/// 自動で入れた項目の id。値が消えている（利用者が空に戻した）項目は含めない。
///
/// 印だけが残って値が無いと、表に「AIが入力」と出るのに空欄、という食い違いになるため。
List<String> autoFilledIds(Map<String, dynamic>? record) {
  final raw = record?[kAutoFilledKey];
  if (raw is! List) return const [];
  return [
    for (final id in raw)
      if (id is String && isFilled(valueOf(record, id))) id,
  ];
}

/// 記録ドキュメントのうち、利用者が「消す」で取り消した項目の id を並べるキー。
/// この項目は、その日はもう自動で埋めない。
const String kAutoRejectedKey = 'autoRejected';

/// 利用者が自動入力を取り消した項目の id。
///
/// 消したあとに日記を作り直すと、AI が同じ値をもう一度入れてしまう。
/// 「違う」という利用者の判断を無視しないために、取り消した項目を覚えておく。
Set<String> autoRejectedIds(Map<String, dynamic>? record) {
  final raw = record?[kAutoRejectedKey];
  if (raw is! List) return const {};
  return {
    for (final id in raw)
      if (id is String) id,
  };
}

/// 提案のうち、自動で入れてよいもの。まだ空の項目だけ。
///
/// 値が入っている項目は、同じ値でも違う値でも触らない。
/// 利用者が表に書いたものを、AI の読み取りで書き換えないため。
/// [rejected] に入っている項目（利用者が取り消したもの）も、空であっても入れない。
List<RecordProposal> autoFillTargets(
  List<RecordProposal> proposals, {
  Set<String> rejected = const {},
}) => [
  for (final proposal in proposals)
    if (proposal.current == null && !rejected.contains(proposal.field.id))
      proposal,
];

/// 会話を、AI に項目を読み取らせる文章にする。
///
/// 探偵の質問も添えるのは、「した」「うん」のような短い答えが、
/// 何についての答えかを質問に頼っているため。読み取りの指示で、
/// 事実として読むのは依頼人の発言だけ、と伝えている。
/// 依頼人の発言が1つも無ければ、読み取る材料が無いので空文字。
String transcriptForExtraction(Iterable<TalkLine> lines) {
  final buffer = StringBuffer();
  var hasUser = false;
  for (final line in lines) {
    final text = line.text.trim();
    if (text.isEmpty) continue;
    switch (line.role) {
      case 'ai':
        buffer.writeln('探偵: $text');
      case 'user':
        hasUser = true;
        buffer.writeln('依頼人: $text');
    }
  }
  return hasUser ? buffer.toString().trimRight() : '';
}

/// 自動で入れた内容を、短い一文にする。例: 「睡眠時間 6.5時間 / 運動した はい ほか1件」。
///
/// 全部を並べると長くなるので、[max] 件までにして残りは件数で示す。
String autoFillSummary(List<RecordProposal> applied, {int max = 3}) {
  if (applied.isEmpty) return '';
  final shown = [
    for (final proposal in applied.take(max))
      '${proposal.field.label} ${formatValue(proposal.field, proposal.value) ?? ''}'
          .trim(),
  ];
  final rest = applied.length - shown.length;
  return rest > 0 ? '${shown.join(' / ')} ほか$rest件' : shown.join(' / ');
}
