// 目標の続き具合と、終えた目標の結末を、AI に渡す短い文にする純粋関数群。
//
// なぜ AI に渡すか：
// 聴取の質問も相談室も、これまで目標がどれだけ続いているかを知らなかった。
// 続いたことも、続かなかったことも、自己理解の手がかりになる。
// 一方、全部の記録を渡すと会話が埋もれるので、数を絞った要約だけを渡す。
//
// 数え方は goal_progress.dart と同じ（答えた日だけを母数にする）。
// 画面と AI で、同じ目標の続き具合が食い違わないようにするため。
import '../models/goal.dart';
import 'daily_record.dart';
import 'goal_progress.dart';
import 'streak.dart' show dateKey;

/// 終えた目標の要約に載せる最大件数。古いものまで並べると会話が埋もれる。
const int kMaxClosedGoalsInDigest = 5;

/// 週ごとの推移で振り返る週数。これより前の記録は、続き具合として古すぎる。
const int kContinuityWeeks = 8;

/// 週ごとの推移を作るのに読む記録の日数。
const int kContinuityDays = kContinuityWeeks * 7;

/// 追跡中の目標ごとの、直近の続き具合。目標が無ければ空文字。
///
/// records は FirestoreService.getRecentRecords の戻り値。today を含む直近
/// windowDays 日だけを数える（それより前の記録は、続き具合として古すぎるため）。
String activeGoalsDigest(
  Iterable<Goal> goals,
  Iterable<MapEntry<String, Map<String, dynamic>>> records,
  DateTime today, {
  int windowDays = 14,
}) {
  final window = {
    for (var i = 0; i < windowDays; i++)
      dateKey(DateTime(today.year, today.month, today.day - i)),
  };
  final recent = [
    for (final entry in records)
      if (window.contains(entry.key)) entry,
  ];

  final lines = <String>[];
  for (final goal in goals) {
    if (goal.isEmpty) continue;
    lines.add('- 目標「${goal.title}」（${elapsedLabel(goal, today)}）');
    final step = stepLabel(goal);
    if (step != null) lines.add('  - $step');
    for (final action in goal.actions) {
      lines.add(
        '  - 「${action.label}」: ${_actionState(action, recent, windowDays)}',
      );
    }
  }
  return lines.join('\n');
}

String _actionState(
  GoalAction action,
  List<MapEntry<String, Map<String, dynamic>>> recent,
  int windowDays,
) {
  switch (action.type) {
    case GoalActionType.check:
      final counts = checkCounts(recent, action.answerKey);
      if (counts.answered == 0) return '直近$windowDays日は記録なし';
      return '直近$windowDays日で記録した${counts.answered}日のうち、達成${counts.done}日';
    case GoalActionType.numeric:
      final latest = latestNumeric(recent, action.answerKey);
      if (latest == null) return '直近$windowDays日は記録なし';
      return '直近の値 ${formatNumber(latest)}${action.unit}';
  }
}

/// 追跡中の目標ごとの、週ごとの継続の推移。目標が無ければ空文字。
///
/// 着手日（無ければ [maxWeeks] 週前）から今日までを7日ずつに区切り、
/// 行動項目ごとに週の数を並べる。左が古い週。
/// - チェック型: 週ごとの「達成した日数/記録した日数」（例: 4/5 → 2/6 → 0/0）
/// - 数値型: 週ごとの「記録した日数」（例: 5 → 4 → 0）
///
/// 直近14日の合計だけでは見えない「いつから減ったか」「いつ途切れたか」を、
/// AI がコードで数えた値から読めるようにするためのもの。
/// 区切りは着手日から数える。暦の週にすると、始めた週が短く、率が低く見えるため。
String goalContinuityDigest(
  Iterable<Goal> goals,
  Iterable<MapEntry<String, Map<String, dynamic>>> records,
  DateTime today, {
  int maxWeeks = kContinuityWeeks,
}) {
  // 日付の引き算は UTC で行う（夏時間をまたいでも1日が24時間になるように）
  final end = DateTime.utc(today.year, today.month, today.day);
  final windowStart = end.subtract(Duration(days: maxWeeks * 7 - 1));
  final byDate = {for (final entry in records) entry.key: entry.value};

  final lines = <String>[];
  for (final goal in goals) {
    if (goal.isEmpty || goal.actions.isEmpty) continue;

    var start = windowStart;
    final created = DateTime.tryParse(goal.createdAt);
    if (created != null) {
      final createdDay = DateTime.utc(created.year, created.month, created.day);
      if (createdDay.isAfter(start)) start = createdDay;
    }
    if (start.isAfter(end)) start = end;
    final spanDays = end.difference(start).inDays + 1;
    final weeks = (spanDays + 6) ~/ 7;

    final partial = spanDays % 7;
    final partialNote = partial == 0 ? '' : '。最後の週は$partial日分';
    lines.add(
      '- 目標「${goal.title}」（${elapsedLabel(goal, today)}）: '
      '週ごとの推移、左が古い週$partialNote',
    );
    for (final action in goal.actions) {
      final answered = List<int>.filled(weeks, 0);
      final done = List<int>.filled(weeks, 0);
      for (var offset = 0; offset < spanDays; offset++) {
        final day = start.add(Duration(days: offset));
        final record = byDate[dateKey(day)];
        if (action.type == GoalActionType.check) {
          final flag = flagOf(record, action.answerKey);
          if (flag == null) continue;
          answered[offset ~/ 7]++;
          if (flag) done[offset ~/ 7]++;
        } else if (numberOf(record, action.answerKey) != null) {
          answered[offset ~/ 7]++;
        }
      }
      final trend = action.type == GoalActionType.check
          ? '週ごとの達成日数/記録日数 '
                '${[for (var w = 0; w < weeks; w++) '${done[w]}/${answered[w]}'].join(' → ')}'
          : '週ごとの記録日数 ${answered.join(' → ')}';
      lines.add('  - 「${action.label}」: $trend');
    }
  }
  return lines.join('\n');
}

/// 追跡を終えた目標の結末。新しく終えたものから最大 [limit] 件。無ければ空文字。
///
/// 終え方（解決・断念）と、着手日〜終了日だけを渡す。理由はまだ記録されていないので、
/// 「なぜやめたか」は推測させない文面にしている。
String closedGoalsDigest(
  Iterable<Goal> closedGoals, {
  int limit = kMaxClosedGoalsInDigest,
}) {
  final sorted = [
    for (final goal in closedGoals)
      if (!goal.isEmpty) goal,
  ]..sort(Goal.byClosedDesc);

  return [
    for (final goal in sorted.take(limit))
      '- 目標「${goal.title}」: ${_outcomeLabel(goal.status)}${_period(goal)}',
  ].join('\n');
}

String _outcomeLabel(GoalStatus status) => switch (status) {
  GoalStatus.solved => '解決した',
  GoalStatus.abandoned => '断念した',
  GoalStatus.closed => '追跡を終えた（結末は記録されていない）',
  GoalStatus.active => '追跡中',
};

String _period(Goal goal) {
  if (goal.createdAt.isEmpty && goal.closedAt.isEmpty) return '';
  final from = goal.createdAt.isEmpty ? '着手日不明' : goal.createdAt;
  final to = goal.closedAt.isEmpty ? '終了日不明' : goal.closedAt;
  return '（$from〜$to）';
}
