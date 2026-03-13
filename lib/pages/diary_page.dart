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
// fixed        : 設定ベースの固定質問（睡眠/食事/運動/勉強/recallAssist）
// eventQuestions: 出来事の構造化質問（いつ/どこで/誰が/誰と/何をした/どうだった）
// ai           : AIによる追加質問（1回）
// addendum     : 追記事項の確認
// custom       : ユーザー定義のカスタム質問
// confirm      : 「これでいいですか？」の確認ステップ（ボタンUI）
// done         : 全質問完了・日記生成待ち
enum _Phase { fixed, eventQuestions, ai, addendum, custom, confirm, done }

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
  final Queue<String> _eventQueue = Queue(); // 出来事の構造化質問のキュー
  final Queue<String> _customQueue = Queue(); // ユーザー定義のカスタム質問のキュー

  // 出来事についての構造化された固定質問リスト
  static const List<String> _eventQuestions = [
    'それはいつの出来事ですか？',
    'どこでありましたか？',
    'その出来事の主な登場人物は誰ですか？',
    '誰かと一緒でしたか？',
    '具体的に何をしましたか？',
    'どんな気分・感想でしたか？',
  ];

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

    // 出来事の構造化質問を冒頭に「記録したい出来事についてお聞きします」を付けてキューへ
    _eventQueue.add('記録したい出来事についてお聞きします。');
    _eventQueue.addAll(_eventQuestions);

    for (final q in settings.customQuestions) {
      _customQueue.add(q);
    }
  }

  // 現在のフェーズに応じて次の質問をする
  Future<void> _askNext() async {
    switch (_phase) {
      case _Phase.fixed:
        if (_fixedQueue.isNotEmpty) {
          _postAiMessage(_fixedQueue.removeFirst());
        } else {
          _phase = _Phase.eventQuestions;
          await _askNext();
        }
      case _Phase.eventQuestions:
        if (_eventQueue.isNotEmpty) {
          _postAiMessage(_eventQueue.removeFirst());
        } else {
          // 構造化質問が終わったらAIの追加質問フェーズへ
          _phase = _Phase.ai;
          await _askAiFollowUp();
        }
      case _Phase.addendum:
        _postAiMessage('追記したいことはありますか？（なければ「なし」と入力してください）');
      case _Phase.custom:
        if (_customQueue.isNotEmpty) {
          _postAiMessage(_customQueue.removeFirst());
        } else {
          _phase = _Phase.confirm;
          await _askNext();
        }
      case _Phase.ai:
        break; // AIフェーズは _askAiFollowUp() で直接呼ぶため_askNext()では何もしない
      case _Phase.confirm:
        // 確認ステップはボタンUIで表示するためメッセージだけ投稿する
        _postAiMessage('以上で質問は終わりです。この内容で日記を生成しますか？');
        setState(() {});
      case _Phase.done:
        break;
    }
  }

  // Geminiを呼ばずにメッセージをAI発言としてリストとFirestoreに追加する
  void _postAiMessage(String text) {
    _firestore.saveMessage(_uid!, _today!, 'ai', text, _conversationOrder++);
    setState(() => _messages.add({'role': 'ai', 'text': text}));
  }

  // ユーザーの返答を受け取り、現在のフェーズに応じて次のアクションを決める
  Future<void> _sendUserReply(String text) async {
    if (text.trim().isEmpty) return;
    _textController.clear();

    await _firestore.saveMessage(
        _uid!, _today!, 'user', text, _conversationOrder++);
    setState(() => _messages.add({'role': 'user', 'text': text}));

    switch (_phase) {
      case _Phase.fixed:
        await _askNext();
      case _Phase.eventQuestions:
        // 冒頭の「記録したい出来事について〜」はユーザー返答不要なのでスキップ済み
        // 各構造化質問への回答後、次の質問へ進む
        await _askNext();
      case _Phase.ai:
        // AI追加質問への返答後は追記フェーズへ
        _phase = _Phase.addendum;
        await _askNext();
      case _Phase.addendum:
        // 追記後はカスタム質問フェーズへ
        _phase = _Phase.custom;
        await _askNext();
      case _Phase.custom:
        await _askNext();
      case _Phase.confirm:
        break; // confirmフェーズはボタンで操作するため入力は無視
      case _Phase.done:
        break;
    }
  }

  // Geminiに追加質問を生成させる（AIフェーズで1回呼ばれる）
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
    setState(() {
      _phase = _Phase.done;
      _isLoading = true;
    });
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
    // confirmフェーズはボタンUIを出すためテキスト入力を非表示にする
    final showInput = !_diaryGenerated &&
        !_isLoading &&
        lastIsAI &&
        _phase != _Phase.confirm &&
        _phase != _Phase.done;
    final showConfirmButton = _phase == _Phase.confirm && !_isLoading;

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
          // 「これでいいですか？」確認ボタン
          if (showConfirmButton)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _generateDiary,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5C3D2E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'はい、日記を生成する',
                    style: TextStyle(fontSize: 16),
                  ),
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
