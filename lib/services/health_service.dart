import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:intl/intl.dart';

// Health Connect（Android）からスマートウォッチ等の睡眠データを読み取るサービス。
// 対応プラットフォームはAndroidのみ。Web/iOSでは isSupported が false となり、
// 全メソッドが例外を投げずに null / false / 空を返す（呼び出し側は手動入力にフォールバック）。
class HealthService {
  static final instance = HealthService._();
  HealthService._();

  final Health _health = Health();
  bool _configured = false;

  static const _types = [HealthDataType.SLEEP_SESSION];
  static const _permissions = [HealthDataAccess.READ];

  // healthプラグインはWebでMethodChannelが存在せず、内部でdart:ioのPlatformを
  // 参照するため、kIsWebを先に判定してからプラットフォームを見る
  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  // Health Connect本体が端末で利用可能か（未インストール・要更新の検知）
  Future<bool> isAvailable() async {
    if (!isSupported) return false;
    try {
      await _ensureConfigured();
      final status = await _health.getHealthConnectSdkStatus();
      return status == HealthConnectSdkStatus.sdkAvailable;
    } catch (e) {
      debugPrint('HealthService.isAvailable: $e');
      return false;
    }
  }

  // Play StoreのHealth Connectページを開く（未インストール時の導線）
  Future<void> installHealthConnect() async {
    if (!isSupported) return;
    try {
      await _ensureConfigured();
      await _health.installHealthConnect();
    } catch (e) {
      debugPrint('HealthService.installHealthConnect: $e');
    }
  }

  // 睡眠データの読み取り権限が付与済みか
  Future<bool> hasPermissions() async {
    if (!isSupported) return false;
    try {
      await _ensureConfigured();
      return await _health.hasPermissions(_types, permissions: _permissions) ??
          false;
    } catch (e) {
      debugPrint('HealthService.hasPermissions: $e');
      return false;
    }
  }

  // 睡眠データの読み取り権限をリクエストする（Health Connectの権限画面が開く）。
  // 設定画面のトグルON時にのみ呼ぶこと。拒否されたら false。
  // 注意: ユーザーが2回拒否すると以後のリクエストは恒久的にブロックされ、
  // Health Connectアプリ側の設定からしか許可できなくなる。
  Future<bool> requestPermissions() async {
    if (!isSupported) return false;
    try {
      await _ensureConfigured();
      return await _health.requestAuthorization(_types,
          permissions: _permissions);
    } catch (e) {
      debugPrint('HealthService.requestPermissions: $e');
      return false;
    }
  }

  // 前夜の睡眠時間を時間単位（小数1桁）で返す。
  // 前日18:00〜現在の睡眠セッションを対象とする。
  // データなし・権限なし・非対応環境・取得失敗はすべて null（手動質問にフォールバック）。
  Future<double?> getLastNightSleepHours() async {
    if (!isSupported) return null;
    try {
      if (!(await hasPermissions())) return null;
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day - 1, 18);
      final points = await _health
          .getHealthDataFromTypes(types: _types, startTime: start, endTime: now)
          .timeout(const Duration(seconds: 8));
      final hours = _unionHours(_health.removeDuplicates(points));
      if (hours <= 0) return null;
      return double.parse(hours.toStringAsFixed(1));
    } catch (e) {
      // 取得に失敗しても日記フローは止めない
      debugPrint('HealthService.getLastNightSleepHours: $e');
      return null;
    }
  }

  // 期間内の睡眠時間を日付（YYYY-MM-DD）ごとに返す（過去データのバックフィル用）。
  // 各セッションは「起床日」に帰属させる：終了時刻が18時前ならその日、
  // 18時以降なら翌日（日記のsleepの意味論＝「その日の前夜の睡眠」に合わせる）。
  Future<Map<String, double>> getSleepHoursByDate(
      DateTime from, DateTime to) async {
    if (!isSupported) return {};
    try {
      if (!(await hasPermissions())) return {};
      // from日に帰属する睡眠（前夜分）も拾うため前日18:00から取得する
      final start = DateTime(from.year, from.month, from.day - 1, 18);
      final end = DateTime(to.year, to.month, to.day, 18);
      final points = await _health
          .getHealthDataFromTypes(types: _types, startTime: start, endTime: end)
          .timeout(const Duration(seconds: 15));

      final byDate = <String, List<HealthDataPoint>>{};
      final formatter = DateFormat('yyyy-MM-dd');
      for (final p in _health.removeDuplicates(points)) {
        final wake = p.dateTo;
        final attributed = wake.hour < 18
            ? DateTime(wake.year, wake.month, wake.day)
            : DateTime(wake.year, wake.month, wake.day + 1);
        byDate.putIfAbsent(formatter.format(attributed), () => []).add(p);
      }

      final result = <String, double>{};
      byDate.forEach((date, sessions) {
        final hours = _unionHours(sessions);
        if (hours > 0) result[date] = double.parse(hours.toStringAsFixed(1));
      });
      return result;
    } catch (e) {
      debugPrint('HealthService.getSleepHoursByDate: $e');
      return {};
    }
  }

  // 睡眠セッション群の合計時間を「区間の和集合」で算出する。
  // スマホとウォッチ双方が同じ夜を記録した場合などの重複計上を防ぐ。
  double _unionHours(List<HealthDataPoint> points) {
    final sessions = points
        .where((p) =>
            p.type == HealthDataType.SLEEP_SESSION &&
            p.dateTo.isAfter(p.dateFrom))
        .toList()
      ..sort((a, b) => a.dateFrom.compareTo(b.dateFrom));

    var total = Duration.zero;
    DateTime? curStart;
    DateTime? curEnd;
    for (final s in sessions) {
      if (curEnd == null || s.dateFrom.isAfter(curEnd)) {
        if (curStart != null) total += curEnd!.difference(curStart);
        curStart = s.dateFrom;
        curEnd = s.dateTo;
      } else if (s.dateTo.isAfter(curEnd)) {
        curEnd = s.dateTo;
      }
    }
    if (curStart != null) total += curEnd!.difference(curStart);
    return total.inMinutes / 60.0;
  }
}
