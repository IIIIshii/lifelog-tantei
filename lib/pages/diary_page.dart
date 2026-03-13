import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/user_settings.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/gemini_service.dart';
import '../widgets/message_bubble.dart';
import '../widgets/diary_card.dart';
import '../widgets/input_area.dart';
import 'diary_list_page.dart';

// 質問フェーズを表す列挙型
// fixed: 固定質問（設定ベース）、ai: AI質問、custom: カスタム質問、done: 全質問完了
enum _Phase { fixed, ai, custom, done }

// 今日の日記を作成するページ。AIとの対話を通じて日記を生成する
class DiaryPage extends StatefulWidget {
  const DiaryPage({super.key});

  @override
  State<DiaryPage> createState() => _DiaryPageState();
}

class _DiaryPageState extends State<DiaryPage> {
  String? _uid;
  String? _today; // 今日の日付（YYYY-MM-DD形式）
  int _conversationOrder = 0; // Firestoreに保存するメッセージの順序カウンター
  final List<Map<String, String>> _messages = []; // 画面に表示する会話履歴
  String? _diary; // 生成された日記テキスト
  bool _isLoading = false;
  bool _diaryGenerated = false;
  final TextEditingController _textController = TextEditingController();

  late final GeminiService _gemini;
  final AuthService _auth = AuthService();
  final FirestoreService _firestore = FirestoreService();

  _Phase _phase = _Phase.fixed;
  final Queue<String> _fixedQueue = Queue(); // 設定から生成した固定質問のキュー
  final Queue<String> _customQueue = Queue(); // ユーザー定義のカスタム質問のキュー
  int _aiExchanges = 0; // AIフェーズでのユーザー返答回数

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

  // セッションを初期化する。今日の日記が既にあれば表示し、なければ質問を開始する
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
        return;
      }

      final settings = await _firestore.getUserSettings(_uid!);
      _buildQueues(settings);
      await _askNext();
    } catch (e) {
      _showError('初期化エラー: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ユーザー設定を元に固定質問キューとカスタム質問キューを構築する
  void _buildQueues(UserSettings settings) {
    if (settings.recallAssist) {
      // 思い出しアシストONの場合、時間帯別の質問を3問追加する
      _fixedQueue.addAll([
        '午前中は何をしていましたか？',
        '午後は何をしていましたか？',
        '夜は何をしていましたか？',
      ]);
    }
    if (settings.recordSleep) {
      _fixedQueue.add('昨夜は何時間くらい眠れましたか？');
    }
    if (settings.recordFood) {
      _fixedQueue.add('今日食べたものを教えてください。');
    }
    if (settings.recordExercise) {
      _fixedQueue.add('今日運動しましたか？');
    }
    if (settings.recordStudy) {
      _fixedQueue.add('今日の勉強内容を教えてください。');
    }

    for (final q in settings.customQuestions) {
      _customQueue.add(q);
    }
  }

  // 現在のフェーズに応じて次の質問をする
  Future<void> _askNext() async {
    if (_phase == _Phase.fixed) {
      if (_fixedQueue.isNotEmpty) {
        _postAiMessage(_fixedQueue.removeFirst());
      } else {
        // 固定質問が終わったらAIフェーズへ移行する
        _phase = _Phase.ai;
        await _askAiFirst();
      }
    } else if (_phase == _Phase.custom) {
      if (_customQueue.isNotEmpty) {
        _postAiMessage(_customQueue.removeFirst());
      } else {
        // カスタム質問が終わったら完了フェーズへ移行する
        _phase = _Phase.done;
        setState(() {});
      }
    }
  }

  // Geminiを呼ばずにメッセージをAI発言としてリストとFirestoreに追加する
  void _postAiMessage(String text) {
    _firestore.saveMessage(_uid!, _today!, 'ai', text, _conversationOrder++);
    setState(() => _messages.add({'role': 'ai', 'text': text}));
  }

  // AIフェーズの最初の質問をGeminiに生成させる
  Future<void> _askAiFirst() async {
    setState(() => _isLoading = true);
    try {
      final question = await _gemini.generateFirstQuestion();
      await _firestore.saveMessage(
          _uid!, _today!, 'ai', question, _conversationOrder++);
      setState(() => _messages.add({'role': 'ai', 'text': question}));
    } catch (e) {
      _showError('AIエラー: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ユーザーの返答を受け取り、現在のフェーズに応じて次のアクションを決める
  Future<void> _sendUserReply(String text) async {
    if (text.trim().isEmpty) return;
    _textController.clear();

    await _firestore.saveMessage(
        _uid!, _today!, 'user', text, _conversationOrder++);
    setState(() => _messages.add({'role': 'user', 'text': text}));

    if (_phase == _Phase.fixed) {
      await _askNext();
    } else if (_phase == _Phase.ai) {
      _aiExchanges++;
      if (_aiExchanges < 2) {
        // AIの深堀りは最大2回まで
        await _askAiFollowUp();
      } else {
        _phase = _Phase.custom;
        await _askNext();
      }
    } else if (_phase == _Phase.custom) {
      await _askNext();
    }
  }

  // Geminiに深堀り質問を生成させる
  Future<void> _askAiFollowUp() async {
    setState(() => _isLoading = true);
    try {
      final followUp = await _gemini.generateFollowUp(_messages);
      await _firestore.saveMessage(
          _uid!, _today!, 'ai', followUp, _conversationOrder++);
      setState(() => _messages.add({'role': 'ai', 'text': followUp}));
    } catch (e) {
      _showError('AIエラー: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 会話履歴全体からGeminiに日記を生成させてFirestoreに保存する
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

  // エラーダイアログを表示する
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
    final lastIsAI = _messages.isNotEmpty && _messages.last['role'] == 'ai';
    final showInput = !_diaryGenerated && !_isLoading && lastIsAI;
    // 全フェーズ完了かつ日記未生成の場合に生成ボタンを表示する
    final showGenerateButton =
        _phase == _Phase.done && !_diaryGenerated && !_isLoading;

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
                // 末尾に生成された日記カードを表示する
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
