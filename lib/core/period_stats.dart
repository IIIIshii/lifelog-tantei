// 期間の記録を、AI に渡す前にコードで集計する純粋関数群。
//
// なぜコードで先に数えるか：
// 平均や増減を AI に文章から読み取らせると、数字がぶれて、毎回同じ入力でも
// 違う数字が出うる。コードで数えた値を渡し、AI には言葉にする役だけを任せる。
// 同じ入力なら同じ数字になることを、テストで固められる形にしておく。
//
// 相関（睡眠が短い日は気分が低い、など）は出さない。14日ほどの点では偶然の一致が
// 多く、「関係がある」と読ませてしまうおそれのほうが大きいため。
import '../models/record_field.dart';
import 'daily_record.dart';
import 'streak.dart' show dateKey;

/// 記録のあった日がこれに満たないときは、傾向を言わせない。
const int kMinDaysForTrend = 3;

/// 前半と後半を比べるには、それぞれの半分にこれだけの記録が要る。
const int kMinPointsPerHalf = 2;

/// 期間の集計結果。
class PeriodSummary {
  final DateTime start;
  final DateTime end;
  final int periodDays;

  /// 日々の記録に1つでも値がある日の数。
  final int recordedDays;

  /// 日記がある日の数。
  final int diaryDays;

  /// 記録も日記も無かった日の数。
  final int emptyDays;

  /// 項目ごとの集計の行。値が1つも無い項目は含めない。
  final List<String> fieldLines;

  const PeriodSummary({
    required this.start,
    required this.end,
    required this.periodDays,
    required this.recordedDays,
    required this.diaryDays,
    required this.emptyDays,
    required this.fieldLines,
  });

  /// 傾向を言うには記録が少なすぎるか。
  bool get isSparse => recordedDays < kMinDaysForTrend;

  /// AI に渡す文章にする。
  String toPromptBlock() {
    final buffer = StringBuffer()
      ..writeln('【集計（コードで計算した値。数字はこのまま使い、自分で計算し直さないこと）】')
      ..writeln('期間: ${dateKey(start)}〜${dateKey(end)}（$periodDays日間）')
      ..writeln(
        '記録のあった日: $recordedDays日 / 日記のあった日: $diaryDays日 / '
        '記録も日記も無かった日: $emptyDays日',
      );
    for (final line in fieldLines) {
      buffer.writeln('- $line');
    }
    if (isSparse) {
      buffer.writeln(
        '※記録のあった日が$kMinDaysForTrend日に満たないため、傾向は言えない。'
        '「まだ言えない」と書き、断定しないこと。',
      );
    }
    return buffer.toString().trimRight();
  }
}

/// end を最終日とする periodDays 日間の記録を集計する。
///
/// days は mergeDays の結果（{values, diary} を日付ごとに持つ）。期間の外の日は無視する。
/// fields は fieldIndex の結果。項目の並び順がそのまま行の並び順になる。
PeriodSummary summarizePeriod(
  Iterable<MapEntry<String, Map<String, dynamic>>> days,
  Map<String, RecordField> fields, {
  required DateTime end,
  required int periodDays,
}) {
  final endDay = DateTime(end.year, end.month, end.day);
  final startDay = DateTime(
    endDay.year,
    endDay.month,
    endDay.day - (periodDays - 1),
  );
  // 期間の何日目か（0 始まり）を、日付キーから引く
  final dayIndex = <String, int>{
    for (var i = 0; i < periodDays; i++)
      dateKey(DateTime(startDay.year, startDay.month, startDay.day + i)): i,
  };
  final inPeriod = <int, Map<String, dynamic>>{};
  for (final entry in days) {
    final index = dayIndex[entry.key];
    if (index != null) inPeriod[index] = entry.value;
  }

  var recordedDays = 0;
  var diaryDays = 0;
  var activeDays = 0;
  for (final day in inPeriod.values) {
    final recorded = hasAnyValue(day);
    final diary = ((day['diary'] as String?) ?? '').trim().isNotEmpty;
    if (recorded) recordedDays++;
    if (diary) diaryDays++;
    if (recorded || diary) activeDays++;
  }

  final lines = <String>[];
  for (final field in fields.values) {
    // 集計は AI へ渡す文面になるので、AI に渡さない項目は数えない
    if (!field.shareWithAi) continue;
    final line = _fieldLine(field, inPeriod, periodDays);
    if (line != null) lines.add(line);
  }

  return PeriodSummary(
    start: startDay,
    end: endDay,
    periodDays: periodDays,
    recordedDays: recordedDays,
    diaryDays: diaryDays,
    emptyDays: periodDays - activeDays,
    fieldLines: lines,
  );
}

String? _fieldLine(
  RecordField field,
  Map<int, Map<String, dynamic>> inPeriod,
  int periodDays,
) {
  final label = field.promptLabel;
  switch (field.kind) {
    case FieldKind.numeric:
      return _numericLine(field, label, inPeriod, periodDays);
    case FieldKind.yesNo:
      var recorded = 0;
      var yes = 0;
      for (final day in inPeriod.values) {
        final flag = flagOf(day, field.id);
        if (flag == null) continue;
        recorded++;
        if (flag) yes++;
      }
      if (recorded == 0) return null;
      return '$label: 記録$recorded日のうち、${yesNoLabel(field, true)}が$yes日';
    case FieldKind.choice:
      final counts = <String, int>{};
      for (final day in inPeriod.values) {
        final text = textOf(day, field.id);
        if (text != null) counts[text] = (counts[text] ?? 0) + 1;
      }
      if (counts.isEmpty) return null;
      // 件数の多い順。同数なら名前順にして、並びが毎回同じになるようにする
      final sorted = counts.entries.toList()
        ..sort((a, b) {
          final byCount = b.value.compareTo(a.value);
          return byCount != 0 ? byCount : a.key.compareTo(b.key);
        });
      return '$label: ${sorted.map((e) => '${e.key}${e.value}日').join(' / ')}';
    case FieldKind.text:
      // 自由記述は集計できない。日記と並べて AI が読む
      return null;
  }
}

String? _numericLine(
  RecordField field,
  String label,
  Map<int, Map<String, dynamic>> inPeriod,
  int periodDays,
) {
  final points = <int, double>{};
  for (final entry in inPeriod.entries) {
    final value = numberOf(entry.value, field.id);
    if (value != null) points[entry.key] = value;
  }
  if (points.isEmpty) return null;

  final values = points.values.toList();
  final mean = _mean(values);
  final min = values.reduce((a, b) => a < b ? a : b);
  final max = values.reduce((a, b) => a > b ? a : b);
  final unit = field.unit;
  final buffer = StringBuffer()
    ..write('$label: 記録${values.length}日、平均${_fmt(mean)}$unit')
    ..write('（最小${_fmt(min)}〜最大${_fmt(max)}）');

  // 前半と後半の平均を比べる。どちらかの記録が少ないときは、増減を言わない
  final half = periodDays ~/ 2;
  final first = [
    for (final e in points.entries)
      if (e.key < half) e.value,
  ];
  final second = [
    for (final e in points.entries)
      if (e.key >= half) e.value,
  ];
  if (first.length >= kMinPointsPerHalf && second.length >= kMinPointsPerHalf) {
    buffer.write(
      '、前半の平均${_fmt(_mean(first))}$unit→後半の平均${_fmt(_mean(second))}$unit',
    );
  }
  return buffer.toString();
}

double _mean(List<double> values) =>
    values.reduce((a, b) => a + b) / values.length;

// 小数第1位に丸めて、整数なら .0 を付けない
String _fmt(double value) =>
    formatNumber(double.parse(value.toStringAsFixed(1)));
