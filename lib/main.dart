import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'pages/home_page.dart';

// アプリのエントリーポイント。dotenv→Firebase→テーマロードの順で初期化する
void main() async {
  await dotenv.load(fileName: ".env"); // .envからAPIキーを読み込む（最初に実行）
  WidgetsFlutterBinding.ensureInitialized(); // Flutter初期化
  await Firebase.initializeApp(); // Firebase初期化
  // SharedPreferencesからテーマを読む。await することで最初のフレームから
  // 正しいテーマで描画でき、"デフォルト→選択テーマ"のチラつきを避けられる。
  await ThemeController.instance.load();
  runApp(const MyApp());
}

// アプリのルートウィジェット
// ThemeController の変更を ValueListenableBuilder で購読し、
// MaterialApp.theme を動的に差し替える構成。
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemeName>(
      valueListenable: ThemeController.instance.notifier,
      builder: (context, themeName, _) {
        return MaterialApp(
          title: 'ライフログ探偵',
          theme: buildTheme(themeName),
          home: const HomePage(),
        );
      },
    );
  }
}
