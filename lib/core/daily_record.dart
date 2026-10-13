// 日々の記録（users/{uid}/records/{YYYY-MM-DD}）を扱う純粋関数群。
//
// 記録ドキュメントの形は {values: {項目id: 値}, updatedAt} で、値は Firestore の型のまま
// （数値は num、はい／いいえは bool、選択肢・テキストは String）。
// この形を知っているのはこのファイルだけに留め、画面・プロンプト・集計はここを通す。
//
// UI から切り出しているのは、「未記入」と「0 や いいえ を記録した」の区別、
// 曜日での絞り込み、目標の項目の混ぜ方といった、取り違えても画面上は正常に見える
// 判断をテストで固めるため。

import '../models/goal.dart';
import '../models/record_field.dart';
import 'numeric_answer.dart';
import 'question_schedule.dart';
import 'streak.dart';

// ──────────────────────────────────────────────────────────────
// 値の取り出し
// ──────────────────────────────────────────────────────────────

/// 記録ドキュメントの values。ドキュメントが無い日・values を持たない日は null。
Map<String, dynamic>? valuesOf(Map<String, dynamic>? record) {
  final values = record?['values'];
  return values is Map<String, dynamic> ? values : null;
}

/// 値が「記録されている」か。空文字は未記入として扱う
/// （テキスト欄を消したときに空文字が残っても、記録済みに数えないため）。
bool isFilled(Object? value) {
  if (value == null) return false;
  if (value is String) return value.trim().isNotEmpty;
  return value is num || value is bool;
}

/// 項目1つの値。未記入なら null。
Object? valueOf(Map<String, dynamic>? record, String fieldId) {
  final value = valuesOf(record)?[fieldId];
  return isFilled(value) ? value : null;
}

/// 数値として記録された値。int で保存されていても double で返す。
double? numberOf(Map<String, dynamic>? record, String fieldId) {
  final value = valueOf(record, fieldId);
  return value is num ? value.toDouble() : null;
}

/// はい／いいえで記録された値。
bool? flagOf(Map<String, dynamic>? record, String fieldId) {
  final value = valueOf(record, fieldId);
  return value is bool ? value : null;
}

/// 選択肢・テキストで記録された値。
String? textOf(Map<String, dynamic>? record, String fieldId) {
  final value = valueOf(record, fieldId);
  return value is String ? value.trim() : null;
}

/// その日に1つでも記録があるか。
bool hasAnyValue(Map<String, dynamic>? record) =>
    valuesOf(record)?.values.any(isFilled) ?? false;

// ──────────────────────────────────────────────────────────────
// 入力値の正規化
// ──────────────────────────────────────────────────────────────

/// 画面から入ってきた値を、項目の型に合う保存値へ直す。
/// 記録として成り立たないもの（空欄・数字の無い数値欄・選択肢に無い値）は null
/// ＝「未記入に戻す」として扱う。
///
/// 数値欄は全角数字や単位付き（「７.５時間」「62kg」）でも拾う。
/// 取りこぼすと値が静かに消え、分析室のグラフから欠けたことに気づけないため。
Object? normalizeInput(RecordField field, Object? raw) {
  switch (field.kind) {
    case FieldKind.numeric:
      if (raw is num) return raw;
      if (raw is String) return parseNumericAnswer(raw);
      return null;
    case FieldKind.yesNo:
      return raw is bool ? raw : null;
    case FieldKind.choice:
      return raw is String && field.choices.contains(raw) ? raw : null;
    case FieldKind.text:
      if (raw is! String) return null;
      final trimmed = raw.trim();
      return trimmed.isEmpty ? null : trimmed;
  }
}

// ──────────────────────────────────────────────────────────────
// 表示
// ──────────────────────────────────────────────────────────────

/// はい／いいえ型の表示。目標の項目は「達成／未達」、それ以外は「はい／いいえ」。
/// 目標の項目は「やったかどうか」を追うものなので、達成の語で揃えている。
String yesNoLabel(RecordField field, bool value) {
  if (field.isGoal) return value ? kGoalDone : kGoalNotDone;
  return value ? 'はい' : 'いいえ';
}

/// 数値を表示用の文字列にする。整数で記録されたものに .0 を付けない
/// （8000歩 を 8000.0歩 と出さない）。
String formatNumber(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(1);

/// 記録された値を人が読む形にする。未記入なら null。
String? formatValue(RecordField field, Object? value) {
  if (!isFilled(value)) return null;
  switch (field.kind) {
    case FieldKind.numeric:
      if (value is! num) return '$value';
      final text = formatNumber(value.toDouble());
      return field.unit.isEmpty ? text : '$text${field.unit}';
    case FieldKind.yesNo:
      if (value is! bool) return '$value';
      return yesNoLabel(field, value);
    case FieldKind.choice:
    case FieldKind.text:
      return '$value'.trim();
  }
}

// ──────────────────────────────────────────────────────────────
// その日の表に出す項目
// ──────────────────────────────────────────────────────────────

/// その日の表に並べる項目。生活の記録（使っている項目のうち、その曜日に出すもの）の
/// 後ろに、追跡中の目標の行動項目を続ける。
///
/// 目標の項目は着手日より前の日には出さない（まだ追っていなかった日が達成率の
/// 母数に入るため）。全目標で kMaxTotalGoalActions 件までに切り詰めるのは、
/// 相談室で守っている上限を、上限導入前のデータでも表の長さに反映させるため。
List<RecordField> fieldsForDay(
  Iterable<RecordField> fields,
  Iterable<Goal> goals,
  DateTime day,
) {
  final key = dateKey(day);
  return [
    for (final field in fields)
      if (field.active && isFieldShownOn(field, day)) field,
    for (final item in buildGoalQuestionQueue(goalsTrackedOn(goals, key)))
      RecordField.fromGoalAction(item.goal, item.action),
  ];
}

/// 表の記入状況。ホームの「日々の記録 3/6」と、捜査の動線で記録を挟むかの判定に使う。
({int filled, int total}) recordProgress(
  Iterable<RecordField> fields,
  Map<String, dynamic>? record,
) {
  var filled = 0;
  var total = 0;
  for (final field in fields) {
    total++;
    if (valueOf(record, field.id) != null) filled++;
  }
  return (filled: filled, total: total);
}

// ──────────────────────────────────────────────────────────────
// AI へ渡す要約
// ──────────────────────────────────────────────────────────────

/// その日の記録を「- ラベル: 値」の行にする。記録が無ければ空文字。
///
/// diaryOnly を true にすると、日記の材料にしない項目（useInDiary: false）を外す。
/// 話題の候補出しには全部を渡し、本文の生成には日記に使う項目だけを渡すため。
String recordSummary(
  Iterable<RecordField> fields,
  Map<String, dynamic>? record, {
  bool diaryOnly = false,
}) {
  final lines = <String>[];
  for (final field in fields) {
    if (diaryOnly && !field.useInDiary) continue;
    final text = formatValue(field, valueOf(record, field.id));
    if (text == null) continue;
    lines.add('- ${field.promptLabel}: $text');
  }
  return lines.join('\n');
}

/// 話題の候補を AI が出せなかったときの代わり。記録のテキスト項目に書かれた
/// 内容（「近所のカフェで本を読んだ」など）をそのまま見出しにする。
///
/// テキストが1つも無ければ空。呼び出し側は定型の見出しで補う。
/// 長い記述はボタンに収まらないので max 文字で切る。
List<String> topicHintsFromRecord(
  Iterable<RecordField> fields,
  Map<String, dynamic>? record, {
  int count = 3,
  int maxLength = 20,
}) {
  final hints = <String>[];
  for (final field in fields) {
    if (field.kind != FieldKind.text || !field.useInDiary) continue;
    final text = textOf(record, field.id);
    if (text == null) continue;
    final hint = text.length > maxLength
        ? '${text.substring(0, maxLength)}…'
        : text;
    if (!hints.contains(hint)) hints.add(hint);
    if (hints.length >= count) break;
  }
  return hints;
}

/// 項目 id → 項目。分析室・所見のプロンプトで、保存された値のキーを
/// 「何を記録したものか」へ戻すために使う。
///
/// 使わなくなった項目（active: false）も含める。過去の記録を読むときには、
/// 今は使っていない項目の値も意味を持つため。
/// 目標は追跡を終えたものも渡してよい（解決済みの事件の記録も過去には残っている）。
Map<String, RecordField> fieldIndex(
  Iterable<RecordField> fields,
  Iterable<Goal> goals,
) => {
  for (final field in fields) field.id: field,
  for (final goal in goals)
    for (final action in goal.actions)
      action.answerKey: RecordField.fromGoalAction(goal, action),
};

// ──────────────────────────────────────────────────────────────
// 日付で記録と日記を重ねる
// ──────────────────────────────────────────────────────────────

/// 記録（records）と日記（diaries）を日付で1枚に重ねる。
/// 戻り値の各 Map は {'values': ..., 'diary': 本文} の形で、どちらか片方だけの日も残す。
///
/// 所見・今日のコメントは「その日に何を記録し、何を書いたか」をまとめて読むので、
/// 渡す直前にここで合わせる。元の Map は書き換えない（画面のキャッシュを壊さない）。
List<MapEntry<String, Map<String, dynamic>>> mergeDays(
  Iterable<MapEntry<String, Map<String, dynamic>>> records,
  Iterable<MapEntry<String, Map<String, dynamic>>> diaries,
) {
  final merged = <String, Map<String, dynamic>>{};
  for (final entry in records) {
    final values = valuesOf(entry.value);
    if (values == null || !values.values.any(isFilled)) continue;
    merged.putIfAbsent(entry.key, () => <String, dynamic>{})['values'] =
        Map<String, dynamic>.of(values);
  }
  for (final entry in diaries) {
    final text = (entry.value['text'] as String?)?.trim() ?? '';
    if (text.isEmpty) continue;
    merged.putIfAbsent(entry.key, () => <String, dynamic>{})['diary'] = text;
  }
  final keys = merged.keys.toList()..sort();
  return [for (final key in keys) MapEntry(key, merged[key]!)];
}

/// 記録をつけた日の集合。日々の記録に1つでも値がある日と、日記がある日の和。
/// ホームの連続日数・ヒートマップ・分析室の連続記録が同じ定義を使う。
Set<String> recordedDates(
  Iterable<MapEntry<String, Map<String, dynamic>>> records,
  Iterable<MapEntry<String, Map<String, dynamic>>> diaries,
) => {
  for (final entry in records)
    if (hasAnyValue(entry.value)) entry.key,
  for (final entry in diaries)
    if (((entry.value['text'] as String?) ?? '').trim().isNotEmpty) entry.key,
};
