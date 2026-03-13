import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'services/firestore_service.dart';
import 'services/notification_service.dart';
import 'pages/home_page.dart';

void main() async {
  await dotenv.load(fileName: ".env");
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await initializeDateFormatting('ja_JP');
  await NotificationService().initialize();
  await _restoreNotification();
  runApp(const MyApp());
}

/// 保存済みの通知設定でリスケジュールする
Future<void> _restoreNotification() async {
  try {
    final credential =
        await FirebaseAuth.instance.signInAnonymously();
    final uid = credential.user?.uid;
    if (uid == null) return;
    final settings = await FirestoreService().getUserSettings(uid);
    if (settings.notificationEnabled) {
      await NotificationService().scheduleDailyNotification(
          settings.notificationHour, settings.notificationMinute);
    }
  } catch (_) {
    // 通知の復元に失敗しても起動は続ける
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ライフログ探偵',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const HomePage(),
    );
  }
}
