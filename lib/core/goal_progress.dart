// 目標の進捗を、保存済みの事件簿エントリ群から算出する純粋関数群。
//
// なぜ純粋関数として切り出すか：
// 進捗は「答えた日だけを母数にする」「記録の無い日と未達の日は違う」といった
// 取り違えやすい数え方の上に成り立っている。UI から独立させておけば
// 単体テストで検証でき、ホームのハイライトと分析室で同じ定義を共有できる。
//
// 引数の entries には FirestoreService.getRecentEntries の戻り値
// （(YYYY-MM-DD, ドキュメントのMap) のリスト）をそのまま渡せる。順序は問わない。
// answerKey には GoalAction.answerKey（'goal_<id>'）を渡すこと。

import '../models/goal.dart';

// エントリ1件から、指定した行動項目への回答文字列を取り出す。
// 未回答・空文字・スキップした日は null を返す。
String? _answerOf(Map<String, dynamic> data, String answerKey) {
  final answers = data['answers'] as Map<String, dynamic>?;
  final value = answers?[answerKey];
  return value is String && value.isNotEmpty ? value : null;
}

// エントリ1件から、指定した行動項目の数値を取り出す。
// 数値として控えられなかった回答（パースに失敗した自由記述）は null を返す。
double? _numericOf(Map<String, dynamic> data, String answerKey) {
  final numeric = data['numericAnswers'] as Map<String, dynamic>?;
  final value = numeric?[answerKey];
  return value is num ? value.toDouble() : null;
}

/// チェック型の行動項目の達成率（0.0〜1.0）。一度も答えていなければ null。
///
/// 母数は「その項目に答えた日」だけで、答えなかった日・スキップした日は数えない。
/// 記録を始める前の日まで未達に数えると、続けるほど率が下がって見えてしまうため。
double? checkRate(
  List<MapEntry<String, Map<String, dynamic>>> entries,
  String answerKey,
) {
  var answered = 0;
  var done = 0;
  for (final entry in entries) {
    final answer = _answerOf(entry.value, answerKey);
    // 想定外の文字列（旧データや手動編集）は母数にも分子にも入れない
    if (answer != kGoalDone && answer != kGoalNotDone) continue;
    answered++;
    if (answer == kGoalDone) done++;
  }
  if (answered == 0) return null;
  return done / answered;
}

/// 数値型の行動項目の最新値。記録が無ければ null。
///
/// entries の並び順に依存しないよう、日付キーの大きい方を採る
/// （'YYYY-MM-DD' は辞書順と時系列順が一致する）。
double? latestNumeric(
  List<MapEntry<String, Map<String, dynamic>>> entries,
  String answerKey,
) {
  String? latestDate;
  double? latestValue;
  for (final entry in entries) {
    final value = _numericOf(entry.value, answerKey);
    if (value == null) continue;
    if (latestDate == null || entry.key.compareTo(latestDate) > 0) {
      latestDate = entry.key;
      latestValue = value;
    }
  }
  return latestValue;
}

/// 目標を立てた日から today までの経過日数。立てた当日は 0。
/// createdAt が空・不正な形式なら 0 を返す（表示を壊さない側に倒す）。
int daysSince(String createdAt, DateTime today) {
  final start = _parseDateKey(createdAt);
  if (start == null) return 0;
  final end = DateTime.utc(today.year, today.month, today.day);
  final days = end.difference(start).inDays;
  return days < 0 ? 0 : days;
}

/// 'YYYY-MM-DD' を UTC の DateTime にする。解釈できなければ null。
///
/// UTC で作るのは、差分を取るときに夏時間の影響を受けないようにするため
/// （ローカル時刻同士だと DST をまたぐ差が 23h / 25h になり inDays が1ずれる）。
DateTime? _parseDateKey(String key) {
  final parts = key.split('-');
  if (parts.length != 3) return null;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) return null;
  return DateTime.utc(year, month, day);
}

/// その日のエントリに、指定した目標の行動項目への回答が1つでもあるか。
///
/// 接頭辞ではなく、その目標が持つ answerKey の集合で判定する。
/// 目標が複数あると 'goal_' 接頭辞だけでは「どの目標を記録したのか」が分からず、
/// 1件答えただけで全部が記録済みに見えてしまうため。
///
/// 行動項目を持たない目標は常に false。答えるものが無いのに「記録済み」と出すと、
/// 何をしたのか分からないバッジになる（表示側もこの場合はバッジを出さない）。
bool hasAnswerForGoal(Map<String, dynamic>? entry, Goal goal) {
  if (entry == null || goal.actions.isEmpty) return false;
  return goal.actions.any(
    (action) => _answerOf(entry, action.answerKey) != null,
  );
}

/// その日に記録済みの目標 id の集合。
/// ホームと相談室ハブが同じ判定を共有できるよう、集合の形でまとめて返す。
Set<String> goalsRecordedIn(
  Map<String, dynamic>? entry,
  Iterable<Goal> goals,
) => {
  for (final goal in goals)
    if (hasAnswerForGoal(entry, goal)) goal.id,
};
