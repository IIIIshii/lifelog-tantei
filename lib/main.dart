import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'pages/home_page.dart';

// アプリのエントリーポイント。dotenv→Firebase の順で初期化する
void main() async {
  await dotenv.load(fileName: ".env"); // .envからAPIキーを読み込む（最初に実行）
  WidgetsFlutterBinding.ensureInitialized(); // Flutter初期化
  await Firebase.initializeApp(); // Firebase初期化
  runApp(const MyApp());
}

// アプリのルートウィジェット
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
