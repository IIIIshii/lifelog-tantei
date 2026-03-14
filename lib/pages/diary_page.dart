import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../core/theme/detective_theme.dart';
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

// 1つの質問を表すデータクラス
// choices: nullのときはテキスト入力式
// key: answersマップへの保存キー。nullのとき（導入文など）は回答を記録しない
class _Question {
  final String text;
  final List<String>? choices;
  final String? key;
  const _Question(this.text, {this.choices, this.key});
}

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
  String? _existingDiary; // 既存の日記テキスト（追記時に使用）
  bool _isLoading = false;
  bool _diaryGenerated = false;
  bool _showExistingDiaryChoice = false; // 追記 or 確認の選択肢を表示するフラグ
  final TextEditingController _textController = TextEditingController();
  List<String>? _currentChoices; // 現在表示中の選択肢。nullのときはテキスト入力を表示
  String? _pendingKey; // 直前のAI質問のキー（次のユーザー回答をanswersに紐づけるため）
  final Map<String, String> _answers = {}; // 質問キー → 回答テキストのマップ

  late final GeminiService _gemini;
  final AuthService _auth = AuthService();
  final FirestoreService _firestore = FirestoreService();

  _Phase _phase = _Phase.fixed;
  final Queue<_Question> _fixedQueue = Queue(); // 設定から生成した固定質問のキュー
  final Queue<_Question> _eventQueue = Queue(); // 出来事の構造化質問のキュー
  final Queue<_Question> _customQueue = Queue(); // ユーザー定義のカスタム質問のキュー

  // 出来事についての構造化された固定質問リスト（_eventQuestionKeysと順序を合わせること）
  static const List<String> _eventQuestions = [
    'それはいつの出来事ですか？',
    'どこでありましたか？',
    'その出来事の主な登場人物は誰ですか？',
    '誰かと一緒でしたか？',
    '具体的に何をしましたか？',
    'どんな気分・感想でしたか？',
  ];

  // 各出来事質問に対応する answers マップのキー（_eventQuestionsと順序を合わせること）
  static const List<String> _eventQuestionKeys = [
    'event_when',
    'event_where',
    'event_who',
    'event_with',
    'event_what',
    'event_how',
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
          _existingDiary = existingDiary;
          _messages.add({'role': 'ai', 'text': '今日の事件簿がすでにあります。どうしますか？'});
          _showExistingDiaryChoice = true;
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

  // 既存の日記がある場合の選択肢（追記 or 確認）を処理する
  Future<void> _handleExistingDiaryChoice(String choice) async {
    setState(() => _showExistingDiaryChoice = false);
    _messages.add({'role': 'user', 'text': choice});

    if (choice == '日記を確認する') {
      setState(() {
        _diary = _existingDiary;
        _diaryGenerated = true;
      });
      return;
    }

    // 追記する → 通常の質問フローを開始
    setState(() => _isLoading = true);
    try {
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
        const _Question('午前中は何をしていましたか？', key: 'morning'),
        const _Question('午後は何をしていましたか？', key: 'afternoon'),
        const _Question('夜は何をしていましたか？', key: 'evening'),
      ]);
    }
    if (settings.recordSleep) {
      // 睡眠時間は数字選択式
      _fixedQueue.add(const _Question(
        '昨夜は何時間くらい眠れましたか？',
        choices: ['4時間以下', '5時間', '6時間', '7時間', '8時間', '9時間以上'],
        key: 'sleep',
      ));
    }
    if (settings.recordFood) {
      _fixedQueue.add(const _Question('今日食べたものを教えてください。', key: 'food'));
    }
    if (settings.recordExercise) {
      // 筋トレの有無はYes/No選択式
      _fixedQueue.add(const _Question(
        '今日、筋トレをしましたか？',
        choices: ['はい', 'いいえ'],
        key: 'exercise',
      ));
    }
    if (settings.recordStudy) {
      _fixedQueue.add(const _Question('今日の勉強内容を教えてください。', key: 'study'));
    }

    // 冒頭の導入文はkeyなし（ユーザーの回答を伴わないため）
    _eventQueue.add(const _Question('記録したい出来事についてお聞きします。'));
    for (var i = 0; i < _eventQuestions.length; i++) {
      _eventQueue.add(_Question(_eventQuestions[i], key: _eventQuestionKeys[i]));
    }

    for (var i = 0; i < settings.customQuestions.length; i++) {
      _customQueue.add(_Question(settings.customQuestions[i], key: 'custom_$i'));
    }
  }

  // 現在のフェーズに応じて次の質問をする
  Future<void> _askNext() async {
    switch (_phase) {
      case _Phase.fixed:
        if (_fixedQueue.isNotEmpty) {
          final q = _fixedQueue.removeFirst();
          _postAiMessage(q.text, choices: q.choices, key: q.key);
        } else {
          _phase = _Phase.eventQuestions;
          await _askNext();
        }
      case _Phase.eventQuestions:
        if (_eventQueue.isNotEmpty) {
          final q = _eventQueue.removeFirst();
          _postAiMessage(q.text, choices: q.choices, key: q.key);
        } else {
          // 構造化質問が終わったらAIの追加質問フェーズへ
          _phase = _Phase.ai;
          await _askAiFollowUp();
        }
      case _Phase.addendum:
        _postAiMessage('追記したいことはありますか？（なければ「なし」と入力してください）',
            key: 'addendum');
      case _Phase.custom:
        if (_customQueue.isNotEmpty) {
          final q = _customQueue.removeFirst();
          _postAiMessage(q.text, choices: q.choices, key: q.key);
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
  // choices: 指定された場合は選択肢ボタンを表示
  // key: 次のユーザー回答をanswersマップに記録する際のキー
  void _postAiMessage(String text, {List<String>? choices, String? key}) {
    _firestore.saveMessage(_uid!, _today!, 'ai', text, _conversationOrder++);
    setState(() {
      _messages.add({'role': 'ai', 'text': text});
      _currentChoices = choices;
      _pendingKey = key;
    });
  }

  // ユーザーの返答を受け取り、現在のフェーズに応じて次のアクションを決める
  Future<void> _sendUserReply(String text) async {
    if (text.trim().isEmpty) return;
    _textController.clear();
    setState(() => _currentChoices = null); // 選択肢を閉じる

    // 直前の質問にキーがあれば回答をanswersマップに記録する
    if (_pendingKey != null) {
      _answers[_pendingKey!] = text;
      _pendingKey = null;
    }

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
      setState(() {
        _messages.add({'role': 'ai', 'text': followUp});
        _pendingKey = 'ai_followup';
      });
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
      final diary = _existingDiary != null
          ? await _gemini.generateDiaryWithExisting(_existingDiary!, _messages)
          : await _gemini.generateDiary(_messages);
      await Future.wait([
        _firestore.saveDiary(_uid!, _today!, diary),
        _firestore.saveAnswers(_uid!, _today!, _answers),
      ]);
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
    final showChoices = !_diaryGenerated &&
        !_isLoading &&
        lastIsAI &&
        _currentChoices != null &&
        _phase != _Phase.confirm &&
        _phase != _Phase.done;
    // confirmフェーズ・選択肢表示中はテキスト入力を非表示にする
    final showInput = !_diaryGenerated &&
        !_isLoading &&
        lastIsAI &&
        _currentChoices == null &&
        _phase != _Phase.confirm &&
        _phase != _Phase.done;
    final showConfirmButton = _phase == _Phase.confirm && !_isLoading;

    return Scaffold(
      backgroundColor: DetectiveTheme.background,

      // ── AppBar ──────────────────────────────────────────────
      // 設定ページ・ホームと同じくサブタイトル付きで捜査中の雰囲気を演出する
      appBar: AppBar(
        backgroundColor: DetectiveTheme.appBarBg,
        foregroundColor: const Color(0xFFE8DCC8),
        elevation: 0,
        toolbarHeight: 64,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('新規捜査', style: DetectiveTheme.appBarTitle),
            const SizedBox(height: 2),
            const Text('― 証拠を集める ―',
                style: DetectiveTheme.appBarSubtitle),
          ],
        ),
        actions: [
          // 事件簿アーカイブへのショートカットボタン
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: '事件簿アーカイブ',
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
              padding: EdgeInsets.all(12.0),
              // ゴールドのローディングインジケーターでテーマに統一する
              child: CircularProgressIndicator(color: DetectiveTheme.gold),
            ),
          // 追記 or 確認の選択肢ボタン
          if (_showExistingDiaryChoice && !_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: ['追記する', '日記を確認する'].map((choice) {
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ElevatedButton(
                        onPressed: () => _handleExistingDiaryChoice(choice),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF5C3D2E),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: Text(choice),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          // 選択肢ボタン群
          if (!_showExistingDiaryChoice && showChoices)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _currentChoices!.map((choice) {
                  return ElevatedButton(
                    onPressed: () => _sendUserReply(choice),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: DetectiveTheme.gold,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: Text(choice),
                  );
                }).toList(),
              ),
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
                    backgroundColor: DetectiveTheme.gold,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: const Text(
                    '事件簿を作成する',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          if (!_showExistingDiaryChoice && showInput)
            InputArea(controller: _textController, onSubmit: _sendUserReply),
        ],
      ),
    );
  }
}
