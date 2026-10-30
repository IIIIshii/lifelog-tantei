import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/health_daily.dart';

/// Health Connect がこの端末で使えるか。
enum HealthAvailability {
  available, // 使える
  needsInstall, // Health Connect のアプリを入れる（更新する）と使える（Android 13 以前）
  unsupported, // この端末では使えない
}

// 端末の Health Connect から、歩数・睡眠などの記録を読むサービス。
//
// スマートウォッチの記録は、ウォッチのアプリ（Fitbit・Samsung Health など）が
// Health Connect に書いたものを読む（このアプリが直接ウォッチにつながるわけではない）。
// 読んだ記録は HealthSample に写して core/health_daily.dart に渡し、
// 1日分の値にまとめる判断はそちらに任せる。
//
// 読むのはアプリが前面にあるとき（表を開いたとき・聴取を始めるとき）だけ。
// Health Connect の権限は端末ごとなので、「連携したか」も端末に持つ（SharedPreferences）。
// 連携していない端末では、Health Connect を一度も呼ばない。
class HealthService {
  static final instance = HealthService._();
  HealthService._();

  static const _linkedKey = 'health_connect_linked';

  final Health _health = Health();
  bool _configured = false;

  Future<HealthAvailability> availability() async {
    if (!Platform.isAndroid) return HealthAvailability.unsupported;
    try {
      return switch (await _health.getHealthConnectSdkStatus()) {
        HealthConnectSdkStatus.sdkAvailable => HealthAvailability.available,
        HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired =>
          HealthAvailability.needsInstall,
        _ => HealthAvailability.unsupported,
      };
    } catch (e) {
      debugPrint('Health Connect の状態を確かめられなかった: $e');
      return HealthAvailability.unsupported;
    }
  }

  /// Health Connect のアプリを入れる画面（Play ストア）を開く。
  Future<void> installHealthConnect() => _health.installHealthConnect();

  /// この端末で連携したか。読み取りを止めた端末・一度も連携していない端末は false。
  Future<bool> isLinked() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_linkedKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> setLinked(bool linked) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_linkedKey, linked);
  }

  /// 読み取りの権限を求める。Health Connect の画面で、利用者が種類ごとに許可を選ぶ。
  ///
  /// 一部だけ許可されることもあるので、結果は見ない。許可されなかった種類は、
  /// 読んでも空で返ってくるだけ（scanRecent で何が読めたかを確かめる）。
  Future<void> requestAccess() async {
    await _configure();
    await _health.requestAuthorization(_permissionTypes());
  }

  /// 読み取りを止める。Health Connect の権限も取り消す（アプリを開き直すと効く）。
  Future<void> unlink() async {
    await setLinked(false);
    try {
      await _health.revokePermissions();
    } catch (e) {
      debugPrint('Health Connect の権限を取り消せなかった: $e');
    }
  }

  /// day の1日分の値（項目 id → 値）。連携していない・読めないときは空。
  ///
  /// 読めなくても表や聴取は止めない（端末の値は手で入れることもできる補助のため）。
  Future<Map<String, Object>> readDay(
    DateTime day,
    Iterable<HealthMetric> metrics,
  ) async {
    final wanted = metrics.toList();
    if (wanted.isEmpty || !await isLinked()) return const {};
    try {
      await _configure();
      final start = DateTime(day.year, day.month, day.day);
      final end = DateTime(day.year, day.month, day.day + 1);
      final now = DateTime.now();
      final until = end.isAfter(now) ? now : end;
      final types = healthTypesFor(wanted);
      final samples = <HealthSample>[
        // 睡眠は前の晩に始まるので、前の日の0時から読む
        ...await _read(
          types.difference({HcType.steps, HcType.height}),
          DateTime(day.year, day.month, day.day - 1),
          until,
        ),
        // 身長はめったに測らないので、1年前まで遡る（BMI の計算にだけ使う）
        if (types.contains(HcType.height))
          ...await _read(
            {HcType.height},
            start.subtract(const Duration(days: 365)),
            until,
          ),
        if (types.contains(HcType.steps)) ...await _steps(start, until),
      ];
      return healthValuesForDay(samples, day, metrics: wanted);
    } catch (e) {
      debugPrint('端末の記録を読めなかった: $e');
      return const {};
    }
  }

  /// 直近 days 日の記録から、項目ごとのいちばん新しい値を探す（連携の画面で見せる）。
  ///
  /// Health Connect は、権限を許可した日の30日前より古い記録を既定では読ませないので、
  /// 遡るのは30日まで。
  Future<List<HealthFinding>> scanRecent({int days = 30}) async {
    await _configure();
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day - (days - 1));
    // 心拍数は数秒おきに記録されていて、30日分だと重い。直近2日だけ読む
    const recentOnly = {HcType.heartRate};
    final samples = [
      ...await _read(
        healthTypesFor(
          kHealthMetrics,
        ).difference({...recentOnly, HcType.height}),
        start.subtract(const Duration(days: 1)),
        now,
      ),
      ...await _read(
        recentOnly,
        DateTime(now.year, now.month, now.day - 1),
        now,
      ),
      ...await _read(
        {HcType.height},
        start.subtract(const Duration(days: 365)),
        now,
      ),
    ];
    return latestHealthValues(samples, today: now, days: days);
  }

  Future<void> _configure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  // 権限を求める種類。睡眠の段階は睡眠（SLEEP_SESSION）と同じ権限なので、重ねて並べない。
  List<HealthDataType> _permissionTypes() => [
    for (final type in healthTypesFor(kHealthMetrics))
      if (!HcType.sleepStages.contains(type))
        HealthDataType.values.byName(type),
  ];

  Future<List<HealthSample>> _read(
    Set<String> types,
    DateTime from,
    DateTime to,
  ) async {
    if (types.isEmpty || !from.isBefore(to)) return const [];
    final points = await _health.getHealthDataFromTypes(
      types: [for (final type in types) HealthDataType.values.byName(type)],
      startTime: from,
      endTime: to,
    );
    return [for (final point in points) ?_toSample(point)];
  }

  // 歩数は Health Connect に合計させる。スマホとウォッチが同じ時間の歩数を書いていても、
  // Health Connect がアプリの優先順で重なりを除いてくれるため。
  // 記録が無い時間は 0 で返ってくるので、0 は「記録なし」として扱う。
  Future<List<HealthSample>> _steps(DateTime from, DateTime to) async {
    if (!from.isBefore(to)) return const [];
    final total = await _health.getTotalStepsInInterval(from, to);
    if (total == null || total <= 0) return const [];
    return [
      HealthSample(
        type: HcType.steps,
        value: total.toDouble(),
        from: from,
        to: to,
        source: 'health_connect',
      ),
    ];
  }

  HealthSample? _toSample(HealthDataPoint point) {
    final value = switch (point.value) {
      final NumericHealthValue v => v.numericValue.toDouble(),
      final NutritionHealthValue v => v.calories,
      final MenstruationFlowHealthValue v => _flowLevel(v.flow),
      // 運動は値を使わず、時間の長さと種類だけを見る
      WorkoutHealthValue() => 0.0,
      _ => null,
    };
    if (value == null) return null;
    final workout = point.value;
    return HealthSample(
      type: point.type.name,
      value: value,
      from: point.dateFrom,
      to: point.dateTo,
      source: point.sourceName,
      label: workout is WorkoutHealthValue
          ? workout.workoutActivityType.name
          : '',
    );
  }

  // 月経の量を 1=少ない / 2=ふつう / 3=多い / 0=不明 にする（kMenstruationChoices の順）。
  // 「無し」と記録された日は、月経の記録として数えない。
  double? _flowLevel(MenstrualFlow? flow) => switch (flow) {
    MenstrualFlow.light || MenstrualFlow.spotting => 1,
    MenstrualFlow.medium => 2,
    MenstrualFlow.heavy => 3,
    MenstrualFlow.none => null,
    _ => 0,
  };
}
