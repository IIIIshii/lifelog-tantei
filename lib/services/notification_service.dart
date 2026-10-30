import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../core/timezone_resolver.dart';

class NotificationService {
  static final instance = NotificationService._();
  NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    tz.initializeTimeZones();
    // 通知は補助機能なので、ゾーンを取れなくても起動は止めない。
    String? timeZoneName;
    try {
      timeZoneName = await FlutterTimezone.getLocalTimezone();
    } catch (e) {
      debugPrint('端末のタイムゾーンを取得できませんでした: $e');
    }
    tz.setLocalLocation(resolveLocation(timeZoneName));

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings =
        InitializationSettings(android: androidSettings, iOS: iosSettings);

    await _plugin.initialize(settings: settings);

    // 「正確な時刻のアラーム」の許可は、ここでは聞かない。聞くとシステムの設定画面が
    // 起動のたびに開き、ホームを見る前に飛ばされる。通知をオンにする schedule() で聞く。
    await _androidPlugin?.requestNotificationsPermission();
  }

  AndroidFlutterLocalNotificationsPlugin? get _androidPlugin =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  /// 正確な時刻のアラームを使えるか。使えなければ許可を一度だけ頼む。
  /// Android 以外では常に true（予約の方式を選ぶ必要がない）。
  Future<bool> _ensureExactAlarmPermission() async {
    final android = _androidPlugin;
    if (android == null) return true;
    if (await android.canScheduleExactNotifications() ?? false) return true;
    await android.requestExactAlarmsPermission();
    return await android.canScheduleExactNotifications() ?? false;
  }

  Future<void> schedule(int hour, int minute) async {
    await cancel();
    final canUseExact = await _ensureExactAlarmPermission();

    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    const androidDetails = AndroidNotificationDetails(
      'daily_reminder',
      '毎日のリマインダー',
      channelDescription: '設定した時刻に日記を書くよう通知します',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    await _plugin.zonedSchedule(
      id: 0,
      title: '🔍 捜査の時間です',
      body: '今日の出来事を記録してください',
      scheduledDate: scheduled,
      notificationDetails: details,
      // 許可がないのに exact で予約すると例外になる。断られても通知は届くよう、
      // その場合は時刻に幅を持たせる方式に落とす。
      androidScheduleMode: canUseExact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> cancel() async {
    await _plugin.cancel(id: 0);
  }
}
