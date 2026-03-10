import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/gemini_service.dart';
import '../widgets/message_bubble.dart';
import '../widgets/diary_card.dart';
import '../widgets/input_area.dart';
import 'diary_list_page.dart';

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

  late final GeminiService _gemini;
  final AuthService _auth = AuthService();
  final FirestoreService _firestore = FirestoreService();

  @override
  void initState() {
    super.initState();
    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    _gemini = GeminiService(apiKey);
    _initSession();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _initSession() async {
    setState(() => _isLoading = true);
    try {
      _uid = await _auth.signInAnonymously();
      _today = DateTime.now().toIso8601String().split('T')[0];

      final existingDiary = await _firestore.getTodayDiary(_uid!, _today!);
      if (existingDiary != null) {
        setState(() {
          _diary = existingDiary;
          _diaryGenerated = true;
        });
      } else {
        await _startConversation();
      }
    } catch (e) {
      _showError('初期化エラー: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _startConversation() async {
    final question = await _gemini.generateFirstQuestion();
    await _firestore.saveMessage(_uid!, _today!, 'ai', question, _conversationOrder++);
    setState(() => _messages.add({'role': 'ai', 'text': question}));
  }

  Future<void> _sendUserReply(String text) async {
    if (text.trim().isEmpty) return;
    _textController.clear();

    await _firestore.saveMessage(_uid!, _today!, 'user', text, _conversationOrder++);
    setState(() => _messages.add({'role': 'user', 'text': text}));

    final userReplyCount = _messages.where((m) => m['role'] == 'user').length;
    if (userReplyCount < 2) {
      await _askFollowUp();
    } else {
      setState(() {});
    }
  }

  Future<void> _askFollowUp() async {
    setState(() => _isLoading = true);
    try {
      final followUp = await _gemini.generateFollowUp(_messages);
      await _firestore.saveMessage(_uid!, _today!, 'ai', followUp, _conversationOrder++);
      setState(() => _messages.add({'role': 'ai', 'text': followUp}));
    } catch (e) {
      _showError('AIエラー: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _generateDiary() async {
    setState(() => _isLoading = true);
    try {
      final diary = await _gemini.generateDiary(_messages);
      await _firestore.saveDiary(_uid!, _today!, diary);
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

  void _showError(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('エラー'),
        content: SelectableText(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK')),
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
                  return DiaryCard(diary: _diary!);
                }
                final msg = _messages[index];
                return MessageBubble(role: msg['role']!, text: msg['text']!);
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
          if (showInput)
            InputArea(controller: _textController, onSubmit: _sendUserReply),
        ],
      ),
    );
  }
}
