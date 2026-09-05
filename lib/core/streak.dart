// 記録の連続日数・直近の記録有無を算出する純粋関数群。
//
// なぜ純粋関数として切り出すか：
// ホーム画面のヒーローカードでしか使わないが、日付境界の扱い（今日まだ書いていない場合の
// 数え方など）は取り違えやすい。UI から独立させておけば単体テストで検証でき、
// 将来 AnalyticsPage でも同じ定義を再利用できる。
//
// 引数の writtenDates には「diary フィールドが非 null のエントリの日付」だけを渡すこと。
// 会話の途中で終わったドキュメントも entries には存在するため、これを数えると
// 事件簿アーカイブの表示件数（diary_list_page の絞り込みと同基準）とズレる。

/// DateTime を Firestore のドキュメントID と同じ 'YYYY-MM-DD' 形式に整形する。
String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// today を起点とした連続記録日数を返す。
///
/// 今日まだ書いていない場合は昨日から数える。
/// こうしないと「昨日まで7日続けていた人」が、日中ホームを開いた瞬間に
/// 連続0日と表示されてしまい、継続の手応えを不用意に折ってしまう。
/// （昨日も書いていなければ、その時点で 0 が返る）
int calcStreak(Set<String> writtenDates, DateTime today) {
  // 日付の前後移動は Duration ではなく DateTime(y, m, d - 1) で行う。
  // Duration(days: 1) は「24時間」であり、夏時間のある地域では日付がずれうるため。
  DateTime prevDay(DateTime d) => DateTime(d.year, d.month, d.day - 1);

  // 起点を決める：今日書いていれば今日から、書いていなければ昨日から数える
  var cursor = DateTime(today.year, today.month, today.day);
  if (!writtenDates.contains(dateKey(cursor))) {
    cursor = prevDay(cursor);
  }

  var streak = 0;
  while (writtenDates.contains(dateKey(cursor))) {
    streak++;
    cursor = prevDay(cursor);
  }
  return streak;
}

/// 直近 days 日ぶんの「記録があるか」を古い順の bool リストで返す（週間ヒートマップ用）。
/// 末尾が今日になる。days=7 なら [6日前, 5日前, ..., 昨日, 今日]。
List<bool> recentDayFlags(Set<String> writtenDates, DateTime today, int days) {
  final base = DateTime(today.year, today.month, today.day);
  return List<bool>.generate(days, (i) {
    final d = DateTime(base.year, base.month, base.day - (days - 1 - i));
    return writtenDates.contains(dateKey(d));
  });
}
