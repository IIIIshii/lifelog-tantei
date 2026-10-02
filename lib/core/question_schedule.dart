// カスタム質問の出題スケジュールを判定する純粋関数群。
//
// 質問ごとに出題する曜日（1=月〜7=日）を持たせている。判定を UI から切り離し、
// 曜日番号の取り違え（DateTime.weekday は月曜始まり）を単体テストで押さえる。
import '../models/user_settings.dart';

/// 曜日番号（1=月〜7=日）に対応する1文字の表示名。
const List<String> kWeekdayLabels = ['月', '火', '水', '木', '金', '土', '日'];

/// question を date の日に出題するか。
bool isAskedOn(CustomQuestion question, DateTime date) =>
    question.weekdays.contains(date.weekday);

/// weekday（1〜7）をオン/オフした後の曜日リストを返す（昇順）。
///
/// 最後の1曜日はオフにできない（0曜日だと永久に出題されなくなるため）。
/// その場合は元のリストをそのまま返す。
List<int> toggleWeekday(List<int> weekdays, int weekday) {
  final set = weekdays.toSet();
  if (set.contains(weekday)) {
    if (set.length == 1) return weekdays;
    set.remove(weekday);
  } else {
    set.add(weekday);
  }
  return set.toList()..sort();
}

/// 曜日リストを「毎日」「平日」「土日」「月・水・金」のような短い説明にする。
String describeWeekdays(List<int> weekdays) {
  final set = weekdays.toSet();
  if (set.length == 7) return '毎日';
  if (set.length == 5 && set.containsAll([1, 2, 3, 4, 5])) return '平日';
  if (set.length == 2 && set.containsAll([6, 7])) return '土日';
  final sorted = set.toList()..sort();
  return sorted.map((d) => kWeekdayLabels[d - 1]).join('・');
}
