// 端末（Health Connect）から読んだ値を、日々の記録の1日分にまとめる純粋関数群。
//
// スマートウォッチの記録は、ウォッチのアプリ（Fitbit・Samsung Health など）が
// Health Connect に書いたものを読む。読めるのは「何時から何時に何歩」のような
// 細切れの記録なので、ここで「その日の歩数」のような1日1つの値にまとめる。
//
// 画面やサービスから切り出しているのは、睡眠をどの日の分にするか、
// 2つのアプリが同じ歩数を書いたときに二重に数えないか、手で入れた値を上書きしないか、
// といった判断が、間違えても画面上は正常に見えるため（端末なしのテストで固める）。
// health パッケージの型はここに持ち込まない。サービスが HealthSample に写してから渡す。
import 'dart:math' as math;

import '../models/record_field.dart';
import 'auto_fill.dart';
import 'daily_record.dart';

// ──────────────────────────────────────────────────────────────
// 端末から読んだ値
// ──────────────────────────────────────────────────────────────

/// 読む種類の名前。health パッケージの HealthDataType の名前と同じ文字列。
abstract final class HcType {
  static const steps = 'STEPS';
  static const distance = 'DISTANCE_DELTA';
  static const floors = 'FLIGHTS_CLIMBED';
  static const activeEnergy = 'ACTIVE_ENERGY_BURNED';
  static const totalEnergy = 'TOTAL_CALORIES_BURNED';
  static const basalEnergy = 'BASAL_ENERGY_BURNED';
  static const workout = 'WORKOUT';
  static const sleepSession = 'SLEEP_SESSION';
  static const sleepAsleep = 'SLEEP_ASLEEP';
  static const sleepLight = 'SLEEP_LIGHT';
  static const sleepDeep = 'SLEEP_DEEP';
  static const sleepRem = 'SLEEP_REM';
  static const sleepAwake = 'SLEEP_AWAKE';
  static const sleepAwakeInBed = 'SLEEP_AWAKE_IN_BED';
  static const sleepOutOfBed = 'SLEEP_OUT_OF_BED';
  static const sleepUnknown = 'SLEEP_UNKNOWN';
  static const heartRate = 'HEART_RATE';
  static const restingHeartRate = 'RESTING_HEART_RATE';
  static const hrv = 'HEART_RATE_VARIABILITY_RMSSD';
  static const respiratoryRate = 'RESPIRATORY_RATE';
  static const bloodOxygen = 'BLOOD_OXYGEN';
  static const weight = 'WEIGHT';
  static const height = 'HEIGHT';
  static const bodyFat = 'BODY_FAT_PERCENTAGE';
  static const leanMass = 'LEAN_BODY_MASS';
  static const bodyWater = 'BODY_WATER_MASS';
  static const systolic = 'BLOOD_PRESSURE_SYSTOLIC';
  static const diastolic = 'BLOOD_PRESSURE_DIASTOLIC';
  static const bodyTemperature = 'BODY_TEMPERATURE';
  static const bloodGlucose = 'BLOOD_GLUCOSE';
  static const water = 'WATER';
  static const nutrition = 'NUTRITION';
  static const menstruation = 'MENSTRUATION_FLOW';

  /// 睡眠の段階。どれも睡眠全体（sleepSession）の時間の中に入っている。
  static const sleepStages = [
    sleepAsleep,
    sleepLight,
    sleepDeep,
    sleepRem,
    sleepAwake,
    sleepAwakeInBed,
    sleepOutOfBed,
    sleepUnknown,
  ];

  /// 眠っていなかった段階。睡眠時間からはこの分を引く。
  static const sleepAwakeStages = [sleepAwake, sleepAwakeInBed, sleepOutOfBed];
}

/// 端末から読んだ記録の1件。
class HealthSample {
  /// 種類（HcType のどれか）。
  final String type;

  /// 値。単位は種類ごとに決まっている（歩数は歩、距離は m、水は L、体重は kg、
  /// 運動・睡眠は値を使わず時間の長さで数える、月経は 0〜3 の量）。
  final double value;

  /// 記録の始まりと終わり。体重のようにある時点の値は、両方が同じ時刻。
  final DateTime from;
  final DateTime to;

  /// 書いたアプリ（パッケージ名）。同じ種類を2つのアプリが書いたときに見分ける。
  final String source;

  /// 運動の種類（'RUNNING' など）。それ以外は空。
  final String label;

  HealthSample({
    required this.type,
    required this.value,
    required this.from,
    DateTime? to,
    this.source = '',
    this.label = '',
  }) : to = to ?? from;

  /// 記録の長さ（分）。
  double get minutes => to.difference(from).inSeconds / 60;
}

// ──────────────────────────────────────────────────────────────
// 取る項目の一覧
// ──────────────────────────────────────────────────────────────

/// 1日分にまとめる方法。
enum HealthReduce {
  total, // その日の合計（歩数・距離・カロリーなど）
  average, // その日の平均（心拍数・血中酸素など）
  last, // その日の最後の値（体重・血圧など、測った時点の値）
  sleepHours, // 眠っていた時間（起きていた段階を引く）
  sleepStages, // 睡眠の段階の合計（分）
  bedtime, // 一番長い睡眠の始まり
  wakeTime, // 一番長い睡眠の終わり
  workoutDone, // 運動の記録があるか
  workoutMinutes, // 運動の時間の合計（分）
  workoutKinds, // 運動の種類
  bmi, // その日の体重と、それまでに記録された身長から計算する
  menstruation, // 月経の量（その日の一番多い量）
}

/// 端末から取る項目の定義。記録の型（RecordField）に足すときの形と、
/// 端末のどの種類をどうまとめるかを持つ。
class HealthMetric {
  /// 値を入れる項目の id。睡眠時間・運動したはプリセットの id、それ以外は `health_` で始まる。
  final String fieldId;
  final String label;
  final FieldKind kind;
  final String unit;
  final List<String> choices;

  /// 連携の画面で並べるときのまとまり。
  final String group;

  /// 読むのに要る種類。権限もこの単位で求める。
  final List<String> types;
  final HealthReduce reduce;

  /// 端末の値に掛ける数（m → km の 0.001 など）。
  final double scale;

  /// 保存する小数の桁数。0 なら整数で入れる。
  final int decimals;

  final bool useInDiary;
  final bool shareWithAi;

  const HealthMetric({
    required this.fieldId,
    required this.label,
    required this.group,
    required this.types,
    required this.reduce,
    this.kind = FieldKind.numeric,
    this.unit = '',
    this.choices = const [],
    this.scale = 1,
    this.decimals = 0,
    this.useInDiary = false,
    this.shareWithAi = true,
  });

  /// 今あるプリセット（睡眠時間・運動した）に値を入れる項目か。
  /// この2つは新しく足さず、使っていなければ使うに切り替えるだけ。
  bool get isPreset => !fieldId.startsWith(kHealthFieldPrefix);

  /// 記録の型として足すときの形。
  RecordField toField() => RecordField(
    id: fieldId,
    label: label,
    kind: kind,
    unit: unit,
    choices: choices,
    source: FieldSource.health,
    useInDiary: useInDiary,
    shareWithAi: shareWithAi,
  );
}

/// 月経の量の選択肢。Health Connect の量（1=少ない, 2=ふつう, 3=多い, 0=不明）の順。
const List<String> kMenstruationChoices = ['少ない', 'ふつう', '多い', '量は不明'];

const String _groupSleep = '睡眠';
const String _groupActivity = '活動';
const String _groupHeart = '心臓・呼吸';
const String _groupBody = '体';
const String _groupOther = 'その他';

/// 端末から取る項目の一覧。連携の画面とその日の読み取りは、この並びで扱う。
///
/// 日記の材料（useInDiary）にするのは、日記の出来事になりやすい睡眠・歩数・運動だけ。
/// 心拍・血圧・血糖・体温・血中酸素・体組成・月経は、最初から AI に渡さない（shareWithAi: false）。
/// 記録には残したいが、外のサービスへ出すかは利用者が決めることなので、送る側に倒さない。
///
/// 身長は入れない（毎日は変わらない。BMI の計算にだけ使う）。速度・活動の強さ・運動のルート・
/// 皮膚温度も入れない（1日の値にしにくい、位置情報の権限が要る、ふだんとの差でしか読めない）。
const List<HealthMetric> kHealthMetrics = [
  // 睡眠
  HealthMetric(
    fieldId: kSleepFieldId,
    label: '睡眠時間',
    unit: '時間',
    group: _groupSleep,
    types: [HcType.sleepSession, ...HcType.sleepStages],
    reduce: HealthReduce.sleepHours,
    decimals: 1,
    useInDiary: true,
  ),
  HealthMetric(
    fieldId: 'health_sleep_deep',
    label: '深い睡眠',
    unit: '分',
    group: _groupSleep,
    types: [HcType.sleepSession, HcType.sleepDeep],
    reduce: HealthReduce.sleepStages,
  ),
  HealthMetric(
    fieldId: 'health_sleep_rem',
    label: 'レム睡眠',
    unit: '分',
    group: _groupSleep,
    types: [HcType.sleepSession, HcType.sleepRem],
    reduce: HealthReduce.sleepStages,
  ),
  HealthMetric(
    fieldId: 'health_sleep_light',
    label: '浅い睡眠',
    unit: '分',
    group: _groupSleep,
    types: [HcType.sleepSession, HcType.sleepLight],
    reduce: HealthReduce.sleepStages,
  ),
  HealthMetric(
    fieldId: 'health_sleep_awake',
    label: '夜中に起きていた時間',
    unit: '分',
    group: _groupSleep,
    types: [HcType.sleepSession, ...HcType.sleepAwakeStages],
    reduce: HealthReduce.sleepStages,
  ),
  HealthMetric(
    fieldId: 'health_bedtime',
    label: '寝た時刻',
    kind: FieldKind.text,
    group: _groupSleep,
    types: [HcType.sleepSession],
    reduce: HealthReduce.bedtime,
    useInDiary: true,
  ),
  HealthMetric(
    fieldId: 'health_wake_time',
    label: '起きた時刻',
    kind: FieldKind.text,
    group: _groupSleep,
    types: [HcType.sleepSession],
    reduce: HealthReduce.wakeTime,
    useInDiary: true,
  ),
  // 活動
  HealthMetric(
    fieldId: 'health_steps',
    label: '歩数',
    unit: '歩',
    group: _groupActivity,
    types: [HcType.steps],
    reduce: HealthReduce.total,
    useInDiary: true,
  ),
  HealthMetric(
    fieldId: 'health_distance',
    label: '移動距離',
    unit: 'km',
    group: _groupActivity,
    types: [HcType.distance],
    reduce: HealthReduce.total,
    scale: 0.001,
    decimals: 1,
  ),
  HealthMetric(
    fieldId: 'health_floors',
    label: '上った階数',
    unit: '階',
    group: _groupActivity,
    types: [HcType.floors],
    reduce: HealthReduce.total,
  ),
  HealthMetric(
    fieldId: 'health_active_calories',
    label: '活動で使ったカロリー',
    unit: 'kcal',
    group: _groupActivity,
    types: [HcType.activeEnergy],
    reduce: HealthReduce.total,
  ),
  HealthMetric(
    fieldId: 'health_total_calories',
    label: '1日の消費カロリー',
    unit: 'kcal',
    group: _groupActivity,
    types: [HcType.totalEnergy],
    reduce: HealthReduce.total,
  ),
  HealthMetric(
    fieldId: kExerciseFieldId,
    label: '運動した',
    kind: FieldKind.yesNo,
    group: _groupActivity,
    types: [HcType.workout],
    reduce: HealthReduce.workoutDone,
    useInDiary: true,
  ),
  HealthMetric(
    fieldId: 'health_workout_minutes',
    label: '運動時間',
    unit: '分',
    group: _groupActivity,
    types: [HcType.workout],
    reduce: HealthReduce.workoutMinutes,
    useInDiary: true,
  ),
  HealthMetric(
    fieldId: 'health_workout_kinds',
    label: '運動の種類',
    kind: FieldKind.text,
    group: _groupActivity,
    types: [HcType.workout],
    reduce: HealthReduce.workoutKinds,
    useInDiary: true,
  ),
  // 心臓・呼吸
  HealthMetric(
    fieldId: 'health_heart_rate',
    label: '平均心拍数',
    unit: '拍/分',
    group: _groupHeart,
    types: [HcType.heartRate],
    reduce: HealthReduce.average,
    shareWithAi: false,
  ),
  HealthMetric(
    fieldId: 'health_resting_heart_rate',
    label: '安静時心拍数',
    unit: '拍/分',
    group: _groupHeart,
    types: [HcType.restingHeartRate],
    reduce: HealthReduce.last,
    shareWithAi: false,
  ),
  HealthMetric(
    fieldId: 'health_hrv',
    label: '心拍変動',
    unit: 'ms',
    group: _groupHeart,
    types: [HcType.hrv],
    reduce: HealthReduce.average,
    shareWithAi: false,
  ),
  HealthMetric(
    fieldId: 'health_respiratory_rate',
    label: '呼吸数',
    unit: '回/分',
    group: _groupHeart,
    types: [HcType.respiratoryRate],
    reduce: HealthReduce.average,
    decimals: 1,
    shareWithAi: false,
  ),
  HealthMetric(
    fieldId: 'health_blood_oxygen',
    label: '血中酸素',
    unit: '%',
    group: _groupHeart,
    types: [HcType.bloodOxygen],
    reduce: HealthReduce.average,
    decimals: 1,
    shareWithAi: false,
  ),
  // 体
  HealthMetric(
    fieldId: 'health_weight',
    label: '体重',
    unit: 'kg',
    group: _groupBody,
    types: [HcType.weight],
    reduce: HealthReduce.last,
    decimals: 1,
    shareWithAi: false,
  ),
  HealthMetric(
    fieldId: 'health_body_fat',
    label: '体脂肪率',
    unit: '%',
    group: _groupBody,
    types: [HcType.bodyFat],
    reduce: HealthReduce.last,
    decimals: 1,
    shareWithAi: false,
  ),
  HealthMetric(
    fieldId: 'health_bmi',
    label: 'BMI',
    group: _groupBody,
    types: [HcType.weight, HcType.height],
    reduce: HealthReduce.bmi,
    decimals: 1,
    shareWithAi: false,
  ),
  HealthMetric(
    fieldId: 'health_lean_mass',
    label: '除脂肪体重',
    unit: 'kg',
    group: _groupBody,
    types: [HcType.leanMass],
    reduce: HealthReduce.last,
    decimals: 1,
    shareWithAi: false,
  ),
  HealthMetric(
    fieldId: 'health_body_water',
    label: '体水分量',
    unit: 'kg',
    group: _groupBody,
    types: [HcType.bodyWater],
    reduce: HealthReduce.last,
    decimals: 1,
    shareWithAi: false,
  ),
  // 基礎代謝は「1日あたり何 kcal」という測った時点の値なので、足さずに最後の値を使う
  HealthMetric(
    fieldId: 'health_bmr',
    label: '基礎代謝',
    unit: 'kcal',
    group: _groupBody,
    types: [HcType.basalEnergy],
    reduce: HealthReduce.last,
    shareWithAi: false,
  ),
  // その他
  HealthMetric(
    fieldId: 'health_bp_systolic',
    label: '血圧（上）',
    unit: 'mmHg',
    group: _groupOther,
    types: [HcType.systolic],
    reduce: HealthReduce.last,
    shareWithAi: false,
  ),
  HealthMetric(
    fieldId: 'health_bp_diastolic',
    label: '血圧（下）',
    unit: 'mmHg',
    group: _groupOther,
    types: [HcType.diastolic],
    reduce: HealthReduce.last,
    shareWithAi: false,
  ),
  HealthMetric(
    fieldId: 'health_body_temperature',
    label: '体温',
    unit: '℃',
    group: _groupOther,
    types: [HcType.bodyTemperature],
    reduce: HealthReduce.last,
    decimals: 1,
    shareWithAi: false,
  ),
  HealthMetric(
    fieldId: 'health_blood_glucose',
    label: '血糖値',
    unit: 'mg/dL',
    group: _groupOther,
    types: [HcType.bloodGlucose],
    reduce: HealthReduce.average,
    shareWithAi: false,
  ),
  HealthMetric(
    fieldId: 'health_water',
    label: '飲んだ水の量',
    unit: 'ml',
    group: _groupOther,
    types: [HcType.water],
    reduce: HealthReduce.total,
    scale: 1000,
  ),
  HealthMetric(
    fieldId: 'health_food_calories',
    label: '食事のカロリー',
    unit: 'kcal',
    group: _groupOther,
    types: [HcType.nutrition],
    reduce: HealthReduce.total,
  ),
  HealthMetric(
    fieldId: 'health_menstruation',
    label: '月経',
    kind: FieldKind.choice,
    choices: kMenstruationChoices,
    group: _groupOther,
    types: [HcType.menstruation],
    reduce: HealthReduce.menstruation,
    shareWithAi: false,
  ),
];

/// 項目 id → 端末から取る項目。端末から値を入れられない項目は null。
HealthMetric? healthMetricFor(String fieldId) {
  for (final metric in kHealthMetrics) {
    if (metric.fieldId == fieldId) return metric;
  }
  return null;
}

/// その日の表の項目のうち、端末から値を入れられるもの。
List<HealthMetric> healthMetricsFor(Iterable<RecordField> fields) => [
  for (final field in fields) ?healthMetricFor(field.id),
];

/// 項目を読むのに要る種類（重なりを除く）。
Set<String> healthTypesFor(Iterable<HealthMetric> metrics) => {
  for (final metric in metrics) ...metric.types,
};

// ──────────────────────────────────────────────────────────────
// 1日分にまとめる
// ──────────────────────────────────────────────────────────────

/// day の1日分の値（項目 id → 値）。端末に記録が無い項目は入らない。
///
/// samples は day の前後を含んでいてよい（睡眠は前の晩に始まり、BMI には前に測った
/// 身長が要るため、読む側は広めに読む）。どの記録をその日の分にするかはここで決める:
/// - 睡眠は、その日のうちに終わったもの（前の晩に寝て朝に起きた睡眠は、朝の日の分）
/// - 運動・歩数などの区間の記録は、その日のうちに始まったもの
/// - 体重などの測った時点の値は、その日に測ったもの
Map<String, Object> healthValuesForDay(
  Iterable<HealthSample> samples,
  DateTime day, {
  Iterable<HealthMetric> metrics = kHealthMetrics,
}) => _valuesForDay(_byType(samples), day, metrics);

/// 連携の画面で見せる、項目ごとのいちばん新しい値。
typedef HealthFinding = ({HealthMetric metric, DateTime day, Object value});

/// 直近 days 日の記録から、項目ごとに「値があったいちばん新しい日」とその値を探す。
/// 並びは kHealthMetrics の順。記録が1日も無い項目は入らない。
List<HealthFinding> latestHealthValues(
  Iterable<HealthSample> samples, {
  required DateTime today,
  int days = 30,
  Iterable<HealthMetric> metrics = kHealthMetrics,
}) {
  final byType = _byType(samples);
  final found = <String, HealthFinding>{};
  final pending = [...metrics];
  for (var i = 0; i < days && pending.isNotEmpty; i++) {
    final day = DateTime(today.year, today.month, today.day - i);
    final values = _valuesForDay(byType, day, pending);
    for (final entry in values.entries) {
      final metric = pending.firstWhere((m) => m.fieldId == entry.key);
      found[entry.key] = (metric: metric, day: day, value: entry.value);
    }
    pending.removeWhere((m) => found.containsKey(m.fieldId));
  }
  return [for (final metric in metrics) ?found[metric.fieldId]];
}

Map<String, List<HealthSample>> _byType(Iterable<HealthSample> samples) {
  final byType = <String, List<HealthSample>>{};
  for (final sample in samples) {
    (byType[sample.type] ??= []).add(sample);
  }
  return byType;
}

Map<String, Object> _valuesForDay(
  Map<String, List<HealthSample>> byType,
  DateTime day,
  Iterable<HealthMetric> metrics,
) {
  final start = DateTime(day.year, day.month, day.day);
  final end = DateTime(day.year, day.month, day.day + 1);
  final sleep = _SleepNight.of(byType, start, end);
  final values = <String, Object>{};
  for (final metric in metrics) {
    final value = _reduce(metric, byType, start, end, sleep);
    if (value != null) values[metric.fieldId] = value;
  }
  return values;
}

Object? _reduce(
  HealthMetric metric,
  Map<String, List<HealthSample>> byType,
  DateTime start,
  DateTime end,
  _SleepNight? sleep,
) {
  List<HealthSample> inDay(String type) => [
    for (final s in byType[type] ?? const <HealthSample>[])
      if (_within(s.from, start, end)) s,
  ];
  num? number(double? raw) =>
      raw == null ? null : _round(raw * metric.scale, metric.decimals);

  switch (metric.reduce) {
    case HealthReduce.total:
      final samples = _fromMainSource(
        inDay(metric.types.single),
        (list) => _sum(list.map((s) => s.value)),
      );
      return samples.isEmpty ? null : number(_sum(samples.map((s) => s.value)));
    case HealthReduce.average:
      final samples = _fromMainSource(
        inDay(metric.types.single),
        (list) => list.length.toDouble(),
      );
      return samples.isEmpty
          ? null
          : number(_sum(samples.map((s) => s.value)) / samples.length);
    case HealthReduce.last:
      return number(_latest(inDay(metric.types.single))?.value);
    case HealthReduce.sleepHours:
      return sleep == null ? null : number(sleep.asleepMinutes / 60);
    case HealthReduce.sleepStages:
      if (sleep == null || !sleep.hasStages) return null;
      return number(
        sleep.stageMinutes(metric.types.where((t) => t != HcType.sleepSession)),
      );
    case HealthReduce.bedtime:
      return sleep == null ? null : _clock(sleep.longest.from);
    case HealthReduce.wakeTime:
      return sleep == null ? null : _clock(sleep.longest.to);
    case HealthReduce.workoutDone:
    case HealthReduce.workoutMinutes:
    case HealthReduce.workoutKinds:
      final workouts = _fromMainSource(
        inDay(HcType.workout),
        (list) => _sum(list.map((s) => s.minutes)),
      );
      if (workouts.isEmpty) return null;
      return switch (metric.reduce) {
        HealthReduce.workoutDone => true,
        HealthReduce.workoutMinutes => number(
          _sum(workouts.map((s) => s.minutes)),
        ),
        _ => {for (final w in workouts) workoutLabel(w.label)}.join('、'),
      };
    case HealthReduce.bmi:
      final weight = _latest(inDay(HcType.weight))?.value;
      // 身長はめったに測らないので、その日より前に測ったものも使う
      final height = _latest([
        for (final s in byType[HcType.height] ?? const <HealthSample>[])
          if (s.from.isBefore(end)) s,
      ])?.value;
      if (weight == null || height == null || height <= 0) return null;
      return number(weight / (height * height));
    case HealthReduce.menstruation:
      final flows = inDay(HcType.menstruation);
      if (flows.isEmpty) return null;
      final most = flows.map((s) => s.value.round()).reduce(math.max);
      return most >= 1 && most <= 3
          ? kMenstruationChoices[most - 1]
          : kMenstruationChoices.last;
  }
}

/// その日の睡眠。その日のうちに終わった睡眠と、その中の段階。
class _SleepNight {
  final List<HealthSample> sessions;
  final List<HealthSample> stages;

  _SleepNight(this.sessions, this.stages);

  static _SleepNight? of(
    Map<String, List<HealthSample>> byType,
    DateTime start,
    DateTime end,
  ) {
    final sessions = _fromMainSource([
      for (final s in byType[HcType.sleepSession] ?? const <HealthSample>[])
        if (_within(s.to, start, end)) s,
    ], (list) => _sum(list.map((s) => s.minutes)));
    if (sessions.isEmpty) return null;
    final stages = [
      for (final type in HcType.sleepStages)
        for (final stage in byType[type] ?? const <HealthSample>[])
          if (sessions.any((session) => _contains(session, stage))) stage,
    ];
    return _SleepNight(sessions, stages);
  }

  /// 段階の記録があるか。段階を書かないアプリもあり、その場合「深い睡眠 0分」とは言えない。
  bool get hasStages => stages.isNotEmpty;

  /// 眠っていた時間（分）。寝ていた時間から、夜中に起きていた段階を引く。
  double get asleepMinutes =>
      _sum(sessions.map((s) => s.minutes)) -
      stageMinutes(HcType.sleepAwakeStages);

  double stageMinutes(Iterable<String> types) {
    final wanted = types.toSet();
    return _sum([
      for (final stage in stages)
        if (wanted.contains(stage.type)) stage.minutes,
    ]);
  }

  /// 一番長い睡眠。昼寝があっても、寝た時刻・起きた時刻は夜の睡眠で決める。
  HealthSample get longest =>
      sessions.reduce((a, b) => b.minutes > a.minutes ? b : a);
}

/// 同じ種類を複数のアプリが書いていたら、一番多く記録しているアプリの分だけを残す。
///
/// スマホとウォッチの両方が歩数を数えていると、足し合わせると二重になる。
/// 「多く記録している」の測り方（合計・件数・時間）は種類ごとに weight で渡す。
List<HealthSample> _fromMainSource(
  List<HealthSample> samples,
  double Function(List<HealthSample>) weight,
) {
  if (samples.isEmpty) return samples;
  final bySource = <String, List<HealthSample>>{};
  for (final sample in samples) {
    (bySource[sample.source] ??= []).add(sample);
  }
  if (bySource.length == 1) return samples;
  return bySource.values.reduce((a, b) => weight(b) > weight(a) ? b : a);
}

HealthSample? _latest(List<HealthSample> samples) => samples.isEmpty
    ? null
    : samples.reduce((a, b) => b.to.isAfter(a.to) ? b : a);

bool _within(DateTime t, DateTime start, DateTime end) =>
    !t.isBefore(start) && t.isBefore(end);

bool _contains(HealthSample outer, HealthSample inner) =>
    inner.source == outer.source &&
    !inner.from.isBefore(outer.from) &&
    !inner.to.isAfter(outer.to);

double _sum(Iterable<double> values) => values.fold(0, (a, b) => a + b);

num _round(double value, int decimals) {
  if (decimals == 0) return value.round();
  final factor = math.pow(10, decimals);
  return (value * factor).round() / factor;
}

String _clock(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// 運動の種類（health パッケージの HealthWorkoutActivityType の名前）の日本語名。
/// 一覧に無い種類は「その他の運動」にする。
String workoutLabel(String type) => _workoutLabels[type] ?? 'その他の運動';

const Map<String, String> _workoutLabels = {
  'WALKING': 'ウォーキング',
  'RUNNING': 'ランニング',
  'RUNNING_TREADMILL': 'ランニング（トレッドミル）',
  'HIKING': 'ハイキング',
  'BIKING': 'サイクリング',
  'BIKING_STATIONARY': 'エアロバイク',
  'SWIMMING_POOL': '水泳',
  'SWIMMING_OPEN_WATER': '水泳（屋外）',
  'YOGA': 'ヨガ',
  'PILATES': 'ピラティス',
  'STRENGTH_TRAINING': '筋トレ',
  'WEIGHTLIFTING': 'ウェイトトレーニング',
  'CALISTHENICS': '自重トレーニング',
  'HIGH_INTENSITY_INTERVAL_TRAINING': 'HIIT',
  'ELLIPTICAL': 'クロストレーナー',
  'ROWING': 'ボート',
  'ROWING_MACHINE': 'ローイングマシン',
  'STAIR_CLIMBING': '階段のぼり',
  'STAIR_CLIMBING_MACHINE': 'ステップマシン',
  'DANCING': 'ダンス',
  'SOCIAL_DANCE': 'ダンス',
  'CARDIO_DANCE': 'ダンス',
  'TENNIS': 'テニス',
  'TABLE_TENNIS': '卓球',
  'BADMINTON': 'バドミントン',
  'SQUASH': 'スカッシュ',
  'BASKETBALL': 'バスケットボール',
  'BASEBALL': '野球',
  'SOFTBALL': 'ソフトボール',
  'SOCCER': 'サッカー',
  'VOLLEYBALL': 'バレーボール',
  'HANDBALL': 'ハンドボール',
  'RUGBY': 'ラグビー',
  'GOLF': 'ゴルフ',
  'MARTIAL_ARTS': '武道',
  'BOXING': 'ボクシング',
  'FENCING': 'フェンシング',
  'SKIING': 'スキー',
  'DOWNHILL_SKIING': 'スキー',
  'CROSS_COUNTRY_SKIING': 'クロスカントリースキー',
  'SNOWBOARDING': 'スノーボード',
  'SKATING': 'スケート',
  'ICE_SKATING': 'スケート',
  'SURFING': 'サーフィン',
  'ROCK_CLIMBING': 'クライミング',
  'GYMNASTICS': '体操',
  'GUIDED_BREATHING': '呼吸のエクササイズ',
};

// ──────────────────────────────────────────────────────────────
// 表に入れてよいか
// ──────────────────────────────────────────────────────────────

// 端末から入れた項目の印（kDeviceFilledKey）は daily_record.dart に置いてある。
// 「記録をつけた日」の判定（hasAnyValue）もこの印を見るため。
// AI が会話から入れた印（autoFilled）とは分けて持ち、表には「端末から」と出す。

/// 端末から入れた項目の id。値が消えている項目は含めない（autoFilledIds と同じ考え方）。
List<String> deviceFilledIds(Map<String, dynamic>? record) {
  final raw = record?[kDeviceFilledKey];
  if (raw is! List) return const [];
  return [
    for (final id in raw)
      if (id is String && isFilled(valueOf(record, id))) id,
  ];
}

/// 端末から読んだ値のうち、表に入れてよいもの（項目 id → 値）。
///
/// 入れてよいのは次のどれかで、[fields]（その日の表に出ている項目）に限る:
/// - まだ空の項目
/// - 前に端末から入れた項目で、値が変わったもの（今日の歩数は1日の中で増えていくため）
/// - AI が会話から入れた項目（端末の値の方が正確なので置き換える）
///
/// 利用者が入れた値・直した値には触らない。「消す」で取り消した項目（autoRejected）は、
/// 空でもその日は入れない。値は normalizeInput を通し、項目の型に合わないものは捨てる。
Map<String, Object> deviceFillTargets({
  required Iterable<RecordField> fields,
  required Map<String, Object> readings,
  required Map<String, dynamic>? record,
}) {
  final fromDevice = deviceFilledIds(record).toSet();
  final fromAi = autoFilledIds(record).toSet();
  final rejected = autoRejectedIds(record);
  final targets = <String, Object>{};
  for (final field in fields) {
    final reading = readings[field.id];
    if (reading == null || rejected.contains(field.id)) continue;
    final value = normalizeInput(field, reading);
    if (value == null) continue;
    final current = valueOf(record, field.id);
    final replace =
        current == null ||
        fromAi.contains(field.id) ||
        (fromDevice.contains(field.id) && !_same(current, value));
    if (replace) targets[field.id] = value;
  }
  return targets;
}

/// 記録ドキュメントに、端末から入れる値を重ねたもの。元の Map は書き換えない。
///
/// Firestore への書き込み（FirestoreService.saveDeviceValues）と同じ形にする:
/// 値を入れ、端末の印を足し、AI の印を外す。
Map<String, dynamic> withDeviceValues(
  Map<String, dynamic>? record,
  Map<String, Object> targets,
) {
  final next = Map<String, dynamic>.of(record ?? const {});
  if (targets.isEmpty) return next;
  next['values'] = {...?valuesOf(record), ...targets};
  next[kDeviceFilledKey] = {
    ...?(record?[kDeviceFilledKey] as List?)?.whereType<String>(),
    ...targets.keys,
  }.toList();
  next[kAutoFilledKey] = [
    for (final id in (record?[kAutoFilledKey] as List?) ?? const [])
      if (id is String && !targets.containsKey(id)) id,
  ];
  return next;
}

// 数値は int と double を同じ値として扱う（7 と 7.0 を別物にしない）
bool _same(Object a, Object b) {
  if (a is num && b is num) return a.toDouble() == b.toDouble();
  return a == b;
}
