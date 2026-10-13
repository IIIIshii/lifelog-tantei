// 目標の進捗を、日々の記録（users/{uid}/records/{date}）から算出する純粋関数群。
//
// なぜ純粋関数として切り出すか：
// 進捗は「答えた日だけを母数にする」「記録の無い日と未達の日は違う」といった
// 取り違えやすい数え方の上に成り立っている。UI から独立させておけば
// 単体テストで検証でき、ホーム・相談室・分析室で同じ定義を共有できる。
//
// 目標の行動項目の値は、生活の記録と同じ records/{date} の values に
// 'goal_<actionId>'（GoalAction.answerKey）をキーにして入っている。
// 引数の records には FirestoreService.getRecentRecords の戻り値
// （(YYYY-MM-DD, ドキュメントのMap) のリスト）をそのまま渡せる。順序は問わない。

import '../models/goal.dart';
import 'daily_record.dart';

/// チェック型の行動項目の「答えた日数」と「達成した日数」。
///
/// 母数は「その項目に答えた日」だけで、答えなかった日は数えない。
/// 記録を始める前の日まで未達に数えると、続けるほど率が下がって見えてしまうため。
///
/// 率ではなく件数も返すのは、表示側で母数を添えられるようにするため
/// （率だけだと「1日だけ答えて達成」と「14日続けて達成」がどちらも100%になる）。
({int answered, int done}) checkCounts(
  Iterable<MapEntry<String, Map<String, dynamic>>> records,
  String answerKey,
) {
  var answered = 0;
  var done = 0;
  for (final entry in records) {
    // bool 以外（手で書き換えたデータなど）は母数にも分子にも入れない
    final value = flagOf(entry.value, answerKey);
    if (value == null) continue;
    answered++;
    if (value) done++;
  }
  return (answered: answered, done: done);
}

/// チェック型の行動項目の達成率（0.0〜1.0）。一度も答えていなければ null。
/// 数え方は checkCounts と同じ（答えた日だけを母数にする）。
double? checkRate(
  Iterable<MapEntry<String, Map<String, dynamic>>> records,
  String answerKey,
) {
  final counts = checkCounts(records, answerKey);
  if (counts.answered == 0) return null;
  return counts.done / counts.answered;
}

/// 数値型の行動項目の最新値。記録が無ければ null。
///
/// records の並び順に依存しないよう、日付キーの大きい方を採る
/// （'YYYY-MM-DD' は辞書順と時系列順が一致する）。
double? latestNumeric(
  Iterable<MapEntry<String, Map<String, dynamic>>> records,
  String answerKey,
) {
  String? latestDate;
  double? latestValue;
  for (final entry in records) {
    final value = numberOf(entry.value, answerKey);
    if (value == null) continue;
    if (latestDate == null || entry.key.compareTo(latestDate) > 0) {
      latestDate = entry.key;
      latestValue = value;
    }
  }
  return latestValue;
}

/// 数値項目の推移。日付の古い順に並べた (日付, 値)。グラフの元データ。
List<({String date, double value})> numericSeries(
  Iterable<MapEntry<String, Map<String, dynamic>>> records,
  String answerKey,
) {
  final points = <({String date, double value})>[];
  for (final entry in records) {
    final value = numberOf(entry.value, answerKey);
    if (value != null) points.add((date: entry.key, value: value));
  }
  points.sort((a, b) => a.date.compareTo(b.date));
  return points;
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

/// その日の記録に、指定した目標の行動項目の値が1つでもあるか。
///
/// 'goal_' 接頭辞ではなく、その目標が持つ answerKey の集合で判定する。
/// 目標が複数あると接頭辞だけでは「どの目標を記録したのか」が分からず、
/// 1件答えただけで全部が記録済みに見えてしまうため。
///
/// 行動項目を持たない目標は常に false。答えるものが無いのに「記録済み」と出すと、
/// 何をしたのか分からないバッジになる（表示側もこの場合はバッジを出さない）。
bool hasAnswerForGoal(Map<String, dynamic>? record, Goal goal) {
  if (record == null || goal.actions.isEmpty) return false;
  return goal.actions.any(
    (action) => valueOf(record, action.answerKey) != null,
  );
}

/// その日に記録済みの目標 id の集合。
/// ホームと相談室ハブが同じ判定を共有できるよう、集合の形でまとめて返す。
Set<String> goalsRecordedIn(
  Map<String, dynamic>? record,
  Iterable<Goal> goals,
) => {
  for (final goal in goals)
    if (hasAnswerForGoal(record, goal)) goal.id,
};

/// 「着手から n 日 / 期限 YYYY-MM-DD」の1行。
///
/// createdAt を持たない古い目標では経過を出さない ―― 着手日が分からないものを
/// 「着手から0日」と書くと、今日始めたように見えてしまう。
///
/// 相談室ハブ・分析室・記録一覧が同じ文面を出すため、ここに1本化している。
String elapsedLabel(Goal goal, DateTime today) {
  final deadline = goal.deadline.isEmpty ? '' : ' / 期限 ${goal.deadline}';
  if (goal.createdAt.isEmpty) {
    return deadline.isEmpty ? '着手日は記録されていない' : '期限 ${goal.deadline}';
  }
  return '着手から${daysSince(goal.createdAt, today)}日$deadline';
}
