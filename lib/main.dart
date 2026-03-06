import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  await dotenv.load(fileName: ".env");
  // Flutterの初期化を確実に行う
  WidgetsFlutterBinding.ensureInitialized();
  // Firebaseの初期化
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '天気日記アプリ',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const WeatherQuestionPage(),
    );
  }
}

class WeatherQuestionPage extends StatefulWidget {
  const WeatherQuestionPage({super.key});

  @override
  State<WeatherQuestionPage> createState() => _WeatherQuestionPageState();
}

class _WeatherQuestionPageState extends State<WeatherQuestionPage> {
  String aiResponse = ""; // AIの返信を保存する変数
  bool isLoading = false; // 通信中かどうか

// Geminiと対話する関数
  Future<void> _getAiComment(String weather) async {
    setState(() => isLoading = true);

    try {
      // 1. まずキーを取り出す（nullなら空文字を入れる）
      final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';

      if (apiKey.isEmpty) {
        // キーがない場合の処理（デバッグ時に気づけるようにする）
        print('エラー: APIキーが設定されていません。.envファイルを確認してください。');
        return;
      }

      // 2. モデルを初期化
      final model = GenerativeModel(
        model: 'gemini-2.5-flash', 
        apiKey: apiKey,
      );

      // 2. プロンプト（AIへの命令）を作成
      final prompt = "私は今日の日記を書いています。今日の天気は「$weather」です。これに対して、前向きになれるような短い一言メッセージを1つだけ返してください。";

      // 3. AIに送信
      final response = await model.generateContent([Content.text(prompt)]);
      
      setState(() {
        aiResponse = response.text ?? "AIが言葉に詰まっているようです...";
      });
    } catch (e) {
      setState(() => aiResponse = "エラーが発生しました: $e");
    } finally {
      setState(() => isLoading = false);
    }
  }


  // 匿名ログインを実行し、ユーザーIDを取得する関数
  Future<String?> _signInAnonymously() async {
    final userCredential = await FirebaseAuth.instance.signInAnonymously();
    return userCredential.user?.uid;
  }

  // 天気データをFirestoreに保存する関数
  Future<void> _saveWeather(String weather) async {
  print('--- 保存処理を開始しました ---'); // 追加
  try {
    print('匿名認証を試みています...'); // 追加
    final uid = await _signInAnonymously();
    print('取得したUID: $uid'); // 追加

    if (uid == null) {
      print('UIDが取得できませんでした');
      return;
    }

    final String today = DateTime.now().toIso8601String().split('T')[0];
    print('保存先の日付ドキュメント: $today'); // 追加

    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('entries')
        .doc(today)
        .set({
      'weather': weather,
      'timestamp': FieldValue.serverTimestamp(),
    });

    print('Firestoreへの書き込みに成功しました！'); // 追加
    _getAiComment(weather);
    
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('「$weather」を保存しました！')),
    );
  } catch (e) {
    print('【エラー発生】: $e'); // ここにエラー内容が出るはず
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('保存に失敗しました: $e')),
    );
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('今日の日記')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading) 
              const CircularProgressIndicator() // 読み込み中のぐるぐる
            else if (aiResponse.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(aiResponse, style: const TextStyle(fontSize: 16)),
                  ),
                ),
              ),
            const Text(
              '今日の天気はどうですか？',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _weatherButton('はれ', Colors.orange),
                _weatherButton('あめ', Colors.blue),
                _weatherButton('その他', Colors.grey),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 共通のボタンデザイン
  Widget _weatherButton(String label, Color color) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(backgroundColor: color),
      onPressed: () => _saveWeather(label),
      child: Text(label, style: const TextStyle(color: Colors.white)),
    );
  }
}
