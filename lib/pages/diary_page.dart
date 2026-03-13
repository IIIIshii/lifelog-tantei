import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/question_flow.dart';
import '../models/user_settings.dart';
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
  String? _existingDiary; // 追記前の日記
  bool _isLoading = false;
  bool _diaryGenerated = false;
  bool _isAppending = false;
  UserSettings _settings = UserSettings.defaults();

  List<Question> _questionFlow = [];
  int _nextQuestionIndex = 0;
  bool _afterAllQuestions = false;
  bool _awaitingConfirm = false;

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
      _settings = await _firestore.getUserSettings(_uid!);
      _questionFlow = QuestionFlow.build(_settings);

      final existingDiary = await _firestore.getTodayDiary(_uid!, _today!);
      if (existingDiary != null) {
        setState(() {
          _diary = existingDiary;
          _diaryGenerated = true;
        });
      } else {
        await _askNextQuestion();
      }
    } catch (e) {
      _showError('初期化エラー: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// 次の質問を取得してメッセージに追加する
  Future<void> _askNextQuestion() async {
    if (_nextQuestionIndex >= _questionFlow.length) {
      setState(() {
        _afterAllQuestions = true;
        _awaitingConfirm = true;
      });
      return;
    }

    final question = _questionFlow[_nextQuestionIndex++];

    String text;
    if (question.type == QuestionType.aiFollowUp) {
      setState(() => _isLoading = true);
      try {
        text = await _gemini.generateAIFollowUp(_messages);
      } catch (e) {
        _showError('AIエラー: $e');
        return;
      } finally {
        setState(() => _isLoading = false);
      }
    } else {
      text = question.text;
    }

    await _firestore.saveMessage(
        _uid!, _today!, 'ai', text, _conversationOrder++);
    setState(() => _messages.add({'role': 'ai', 'text': text}));
  }

  Future<void> _sendUserReply(String text) async {
    if (text.trim().isEmpty) return;
    _textController.clear();

    await _firestore.saveMessage(
        _uid!, _today!, 'user', text, _conversationOrder++);
    setState(() => _messages.add({'role': 'user', 'text': text}));

    if (_afterAllQuestions) {
      // 「いいえ（追記する）」後の追加入力 → 確認に戻る
      setState(() => _awaitingConfirm = true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _askNextQuestion();
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// 完成した日記への「追記する」ボタンから呼ばれる
  Future<void> _startAppending() async {
    setState(() {
      _existingDiary = _diary;
      _diary = null;
      _diaryGenerated = false;
      _isAppending = true;
      _messages.clear();
      _nextQuestionIndex = 0;
      _afterAllQuestions = false;
      _awaitingConfirm = false;
    });
    setState(() => _isLoading = true);
    try {
      await _askNextQuestion();
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// 「いいえ（追記する）」タップ時：追記を促すメッセージを表示する
  Future<void> _addMorePrompt() async {
    const prompt = '追記したいことをどうぞ。';
    await _firestore.saveMessage(
        _uid!, _today!, 'ai', prompt, _conversationOrder++);
    setState(() {
      _messages.add({'role': 'ai', 'text': prompt});
      _awaitingConfirm = false;
    });
  }

  Future<void> _generateDiary() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _gemini.generateDiary(_messages, existingDiary: _existingDiary),
        _gemini.extractStats(_messages, _settings),
      ]);
      final diary = results[0] as String;
      final stats = results[1] as Map<String, dynamic>;
      await Future.wait([
        _firestore.saveDiary(_uid!, _today!, diary),
        if (stats.isNotEmpty) _firestore.saveStats(_uid!, _today!, stats),
      ]);
      setState(() {
        _diary = diary;
        _diaryGenerated = true;
        _isAppending = false;
        _existingDiary = null;
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
    final lastIsAI =
        _messages.isNotEmpty && _messages.last['role'] == 'ai';
    final showInput =
        !_diaryGenerated && !_isLoading && lastIsAI && !_awaitingConfirm;
    final showConfirm =
        _awaitingConfirm && !_diaryGenerated && !_isLoading;
    final showAppendButton =
        _diaryGenerated && !_isLoading && !_isAppending;

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
          if (_questionFlow.isNotEmpty && !_diaryGenerated)
            _ProgressBar(
              current: _nextQuestionIndex.clamp(0, _questionFlow.length),
              total: _questionFlow.length,
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + (_diary != null ? 1 : 0),
              itemBuilder: (context, index) {
                if (_diary != null && index == _messages.length) {
                  return DiaryCard(diary: _diary!);
                }
                final msg = _messages[index];
                return MessageBubble(
                    role: msg['role']!, text: msg['text']!);
              },
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(),
            ),
          if (showConfirm)
            _ConfirmBar(
              onYes: _generateDiary,
              onNo: _addMorePrompt,
            ),
          if (showAppendButton)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _startAppending,
                  icon: const Icon(Icons.edit_note),
                  label: const Text('追記する'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF5C3D2E),
                    side: const BorderSide(color: Color(0xFF5C3D2E)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
          if (showInput)
            InputArea(
                controller: _textController, onSubmit: _sendUserReply),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────
// 進捗バー
// ────────────────────────────────────────────
class _ProgressBar extends StatelessWidget {
  final int current;
  final int total;
  const _ProgressBar({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : current / total;
    return Column(
      children: [
        LinearProgressIndicator(
          value: progress,
          backgroundColor: const Color(0xFFE0D8D0),
          valueColor:
              const AlwaysStoppedAnimation<Color>(Color(0xFF5C3D2E)),
          minHeight: 4,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              '$current / $total',
              style:
                  const TextStyle(fontSize: 11, color: Color(0xFF7A5C4A)),
            ),
          ),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────
// 確認バー（これでいいですか？）
// ────────────────────────────────────────────
class _ConfirmBar extends StatelessWidget {
  final VoidCallback onYes;
  final VoidCallback onNo;
  const _ConfirmBar({required this.onYes, required this.onNo});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'これでいいですか？',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onNo,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF5C3D2E),
                    side: const BorderSide(color: Color(0xFF5C3D2E)),
                  ),
                  child: const Text('いいえ（追記する）'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: onYes,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5C3D2E),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('はい、日記を生成'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
