import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  await dotenv.load(fileName: ".env");
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NikkiNext',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const DiaryPage(),
    );
  }
}

class DiaryPage extends StatefulWidget {
  const DiaryPage({super.key});

  @override
  State<DiaryPage> createState() => _DiaryPageState();
}

class _DiaryPageState extends State<DiaryPage> {
  String? _uid;
  String? _today;
  int _conversationOrder = 0;
  final List<Map<String, String>> _messages = [];
  String? _diary;
  bool _isLoading = false;
  bool _diaryGenerated = false;
  final TextEditingController _textController = TextEditingController();
  late final GenerativeModel _model;

  @override
  void initState() {
    super.initState();
    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    _model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: apiKey);
    _initSession();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  // 匿名ログイン・日付設定・最初の質問生成
  Future<void> _initSession() async {
    setState(() => _isLoading = true);
    try {
      final credential = await FirebaseAuth.instance.signInAnonymously();
      _uid = credential.user?.uid;
      _today = DateTime.now().toIso8601String().split('T')[0];
      await _startConversation();
    } catch (e) {
      _showError('初期化エラー: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // AIが最初の質問を生成
  Future<void> _startConversation() async {
    final response = await _model.generateContent([
      Content.text('今日の日記を書くためのインタビューをします。ユーザーに今日の出来事について、親しみやすく短い質問を1つだけしてください。'),
    ]);
    final question = response.text ?? '今日はどんな一日でしたか？';
    await _saveMessage('ai', question);
    setState(() => _messages.add({'role': 'ai', 'text': question}));
  }

  // ユーザーの回答を受け取り、深堀りor日記生成フェーズへ
  Future<void> _sendUserReply(String text) async {
    if (text.trim().isEmpty) return;
    _textController.clear();

    await _saveMessage('user', text);
    setState(() => _messages.add({'role': 'user', 'text': text}));

    final userReplyCount = _messages.where((m) => m['role'] == 'user').length;
    if (userReplyCount < 2) {
      await _askFollowUp();
    } else {
      setState(() {}); // 日記生成ボタンを表示
    }
  }

  // 深堀り質問を生成
  Future<void> _askFollowUp() async {
    setState(() => _isLoading = true);
    try {
      final history = _messages
          .map((m) => '${m['role'] == 'ai' ? 'AI' : 'ユーザー'}: ${m['text']}')
          .join('\n');
      final prompt = '以下は日記インタビューの会話です:\n$history\n\nユーザーの回答に対して、もう少し詳しく聞く自然な深堀り質問を1つだけしてください。';
      final response = await _model.generateContent([Content.text(prompt)]);
      final followUp = response.text ?? 'もう少し詳しく教えてください。';
      await _saveMessage('ai', followUp);
      setState(() => _messages.add({'role': 'ai', 'text': followUp}));
    } catch (e) {
      _showError('AIエラー: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 会話履歴から日記を生成してFirestoreに保存
  Future<void> _generateDiary() async {
    setState(() => _isLoading = true);
    try {
      final history = _messages
          .map((m) => '${m['role'] == 'ai' ? 'AI' : 'ユーザー'}: ${m['text']}')
          .join('\n');
      final prompt = '以下の会話を元に、ユーザーの視点で100〜300字の自然な日記を生成してください。\n\n$history';
      final response = await _model.generateContent([Content.text(prompt)]);
      final diary = response.text ?? '日記を生成できませんでした。';
      await _saveDiary(diary);
      setState(() {
        _diary = diary;
        _diaryGenerated = true;
      });
    } catch (e) {
      _showError('日記生成エラー: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 会話1件をサブコレクションに保存
  Future<void> _saveMessage(String role, String text) async {
    if (_uid == null || _today == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('entries')
        .doc(_today)
        .collection('conversation')
        .add({
          'role': role,
          'text': text,
          'order': _conversationOrder++,
          'timestamp': FieldValue.serverTimestamp(),
        });
  }

  // 生成した日記をentriesドキュメントに保存
  Future<void> _saveDiary(String diary) async {
    if (_uid == null || _today == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('entries')
        .doc(_today)
        .set({
          'diary': diary,
          'timestamp': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  void _showError(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('エラー'),
        content: SelectableText(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userReplyCount = _messages.where((m) => m['role'] == 'user').length;
    final lastIsAI = _messages.isNotEmpty && _messages.last['role'] == 'ai';
    final showInput = !_diaryGenerated && !_isLoading && lastIsAI;
    final showGenerateButton = userReplyCount >= 2 && !_diaryGenerated && !_isLoading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('今日の日記'),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu_book),
            tooltip: '過去の日記',
            onPressed: () {
              if (_uid == null) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DiaryListPage(uid: _uid!),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + (_diary != null ? 1 : 0),
              itemBuilder: (context, index) {
                if (_diary != null && index == _messages.length) {
                  return _diaryCard(_diary!);
                }
                final msg = _messages[index];
                return _messageBubble(msg['role']!, msg['text']!);
              },
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(),
            ),
          if (showGenerateButton)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _generateDiary,
                  child: const Text('日記を生成する'),
                ),
              ),
            ),
          if (showInput) _inputArea(),
        ],
      ),
    );
  }

  Widget _messageBubble(String role, String text) {
    final isAI = role == 'ai';
    return Align(
      alignment: isAI ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: isAI ? Colors.grey[200] : Colors.blue[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(text),
      ),
    );
  }

  Widget _diaryCard(String diary) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 12),
      color: Colors.amber[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('今日の日記', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Text(diary),
          ],
        ),
      ),
    );
  }

  Widget _inputArea() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              decoration: const InputDecoration(
                hintText: '返答を入力...',
                border: OutlineInputBorder(),
              ),
              onSubmitted: _sendUserReply,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: () => _sendUserReply(_textController.text),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────
// 過去の日記一覧画面
// ───────────────────────────────────────────

class DiaryListPage extends StatelessWidget {
  final String uid;
  const DiaryListPage({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    final entriesRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('entries')
        .where('diary', isNotEqualTo: null)
        .orderBy('diary') // isNotEqualToと同フィールドのorderByが必要
        .orderBy('timestamp', descending: true);

    return Scaffold(
      appBar: AppBar(title: const Text('過去の日記')),
      body: StreamBuilder<QuerySnapshot>(
        stream: entriesRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('エラー: ${snapshot.error}'));
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('まだ日記がありません'));
          }
          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final date = docs[index].id; // ドキュメントIDが日付
              final diary = data['diary'] as String? ?? '';
              return ListTile(
                leading: const Icon(Icons.book),
                title: Text(date),
                subtitle: Text(
                  diary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DiaryDetailPage(date: date, diary: diary),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

// ───────────────────────────────────────────
// 日記詳細画面
// ───────────────────────────────────────────

class DiaryDetailPage extends StatelessWidget {
  final String date;
  final String diary;
  const DiaryDetailPage({super.key, required this.date, required this.diary});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(date)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Card(
          color: Colors.amber[50],
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(diary, style: const TextStyle(fontSize: 16, height: 1.8)),
          ),
        ),
      ),
    );
  }
}
