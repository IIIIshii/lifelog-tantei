import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/detective_text_styles.dart';
import '../models/user_settings.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/gemini_service.dart';
import '../widgets/message_bubble.dart';
import '../widgets/diary_card.dart';
import '../widgets/input_area.dart';
import 'diary_list_page.dart';
import 'diary_edit_page.dart';

// 質問フェーズを表す列挙型
// fixed        : 設定ベースの固定質問（睡眠/食事/運動/勉強/recallAssist）
// eventQuestions: 出来事の構造化質問（いつ/どこで/誰が/誰と/何をした/どうだった）
// ai           : AIによる追加質問（1回）
// addendum     : 追記事項の確認
// custom       : ユーザー定義のカスタム質問
// confirm      : 「これでいいですか？」の確認ステップ（ボタンUI）
// done         : 全質問完了・日記生成待ち
enum _Phase {
  custom,      // sleep/food/exercise/study + ユーザーカスタム質問
  customSaved, // カスタム質問回答後「日記に追加しますか？」
  recall,      // 思い出しアシスト（設定ONのみ）
  recallSaved, // 思い出しアシスト後「日記に追加しますか？」
  modeSelect,  // 「質問に沿って作成 / 自分で入力」
  event,       // メインの出来事質問
  aiFollowUp,  // AIによる追加質問
  addendum,    // 追記事項
  diaryView,   // 日記確認（これを記録/編集/生成しなおす/はじめから）
  done,        // 完了
}

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
  bool _viewingExisting = false;         // 既存日記を「確認する」で表示中か
  final TextEditingController _textController = TextEditingController();
  List<String>? _currentChoices; // 現在表示中の選択肢。nullのときはテキスト入力を表示
  String? _pendingKey; // 直前のAI質問のキー（次のユーザー回答をanswersに紐づけるため）
  final Map<String, String> _answers = {}; // 質問キー → 回答テキストのマップ
  final Map<String, double> _numericAnswers = {}; // 質問キー → 数値回答のマップ

  final ScrollController _scrollController = ScrollController();

  late final GeminiService _gemini;
  final AuthService _auth = AuthService();
  final FirestoreService _firestore = FirestoreService();

  _Phase _phase = _Phase.custom;
  bool _includeCustomInDiary = true;  // カスタム質問の回答を日記生成に含めるか
  bool _includeRecallInDiary = true;  // 思い出しアシストの回答を日記生成に含めるか
  bool _hasRecallAssist = false;      // 思い出しアシストが設定ONか
  bool _customIntroPosted = false;    // カスタム質問の導入メッセージ投稿済みか
  bool _recallIntroPosted = false;    // 思い出しアシストの導入メッセージ投稿済みか
  int _eventMsgStart = 0;            // eventフェーズ開始時点の_messagesインデックス
  final Queue<_Question> _customQueue = Queue(); // sleep/food/exercise/study + ユーザーカスタム質問
  final Queue<_Question> _recallQueue = Queue(); // 思い出しアシスト質問
  final Queue<_Question> _eventQueue = Queue();  // メインの出来事質問

  // メインの出来事質問リスト（_eventQuestionKeysと順序を合わせること）
  static const List<_Question> _eventQuestions = [
    _Question(
      'それはいつの話だ？',
      choices: ['朝', '昼', '夜', '仕事中', '学校', 'プライベート', 'その他(自由記述)'],
      key: 'event_when',
    ),
    _Question(
      'どこで起きた？',
      choices: ['自宅', '学校', '職場', 'その他(自由記述)'],
      key: 'event_where',
    ),
    _Question(
      '誰に関わる話だ？',
      choices: ['自分', 'その他(自由記述)'],
      key: 'event_who',
    ),
    _Question(
      '何があった？話してくれ。',
      key: 'event_what',
    ),
    _Question(
      'そのとき、どう感じた？',
      choices: ['嬉しかった', '面白かった', '悲しかった', '怒った', 'その他(自由記述)'],
      key: 'event_how',
    ),
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
    _scrollController.dispose();
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
        _conversationOrder = await _firestore.getMessageCount(_uid!, _today!);
        const message = '今日の事件簿はすでに存在する。どうするつもりだ？';
        await _firestore.saveMessage(
            _uid!, _today!, 'ai', message, _conversationOrder++);
        setState(() {
          _existingDiary = existingDiary;
          _messages.add({'role': 'ai', 'text': message});
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
    await _firestore.saveMessage(
        _uid!, _today!, 'user', choice, _conversationOrder++);
    setState(() {
      _showExistingDiaryChoice = false;
      _messages.add({'role': 'user', 'text': choice});
    });

    if (choice == '日記を確認する') {
      setState(() {
        _diary = _existingDiary;
        _diaryGenerated = true;
        _viewingExisting = true;
      });
      return;
    }

    // 追記する → 質問フローを開始
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

  // ユーザー設定を元に各質問キューを構築する
  void _buildQueues(UserSettings settings) {
    // ── カスタム質問キュー（sleep/food/exercise/study + ユーザー定義）──
    if (settings.recordSleep) {
      _customQueue.add(const _Question(
        '昨夜は何時間眠った？',
        choices: [
          '〜4時間', '4.5時間', '5時間', '5.5時間', '6時間', '6.5時間',
          '7時間', '7.5時間', '8時間', '8.5時間', '9時間', '9.5時間',
          '10時間', '10.5時間', '11時間', '11.5時間', '12時間', '12.5時間',
          '13時間〜', 'カスタム',
        ],
        key: 'sleep',
      ));
    }
    if (settings.recordFood) {
      _customQueue.add(const _Question('今日、何を口にした？', key: 'food'));
    }
    if (settings.recordExercise) {
      _customQueue.add(const _Question(
        '身体を動かしたか？',
        choices: ['した', 'していない'],
        key: 'exercise',
      ));
    }
    if (settings.recordStudy) {
      _customQueue.add(const _Question(
        '今日、頭を使う作業はしたか？',
        choices: ['した', 'していない'],
        key: 'study',
      ));
    }
    for (var i = 0; i < settings.customQuestions.length; i++) {
      _customQueue.add(_Question(settings.customQuestions[i], key: 'custom_$i'));
    }

    // ── 思い出しアシストキュー ──
    _hasRecallAssist = settings.recallAssist;
    if (settings.recallAssist) {
      _recallQueue.addAll([
        const _Question('午前中の動向を報告してくれ。', key: 'morning'),
        const _Question('午後はどう動いた？', key: 'afternoon'),
        const _Question('夜の動向は？', key: 'evening'),
      ]);
    }

    // ── メインの出来事質問キュー ──
    for (final q in _eventQuestions) {
      _eventQueue.add(q);
    }
  }

  // 現在のフェーズに応じて次の質問をする
  Future<void> _askNext() async {
    switch (_phase) {
      case _Phase.custom:
        if (_customQueue.isEmpty && !_customIntroPosted) {
          // カスタム質問が1つもない場合はrecallへスキップ
          _phase = _Phase.recall;
          await _askNext();
          return;
        }
        if (!_customIntroPosted) {
          _customIntroPosted = true;
          _postAiMessage(
            'まず、いくつか確認させてもらう。',
            choices: ['次へ'],
          );
          return;
        }
        if (_customQueue.isNotEmpty) {
          final q = _customQueue.removeFirst();
          _postAiMessage(q.text, choices: q.choices, key: q.key);
        } else {
          _phase = _Phase.customSaved;
          await _askNext();
        }
      case _Phase.customSaved:
        final hasCustomAnswers = _answers.keys.any((k) =>
            ['sleep', 'food', 'exercise', 'study'].contains(k) ||
            k.startsWith('custom_'));
        if (hasCustomAnswers) {
          _postAiMessage(
            '証言を記録した。これからお聞きする出来事の報告書に、この内容も含めるか？',
            choices: ['はい', 'いいえ'],
          );
        } else {
          _phase = _Phase.recall;
          await _askNext();
        }
      case _Phase.recall:
        if (!_hasRecallAssist) {
          _phase = _Phase.modeSelect;
          await _askNext();
          return;
        }
        if (!_recallIntroPosted) {
          _recallIntroPosted = true;
          _postAiMessage('今日一日の行動を洗いざらい話してもらおう。', choices: ['次へ']);
          return;
        }
        if (_recallQueue.isNotEmpty) {
          final q = _recallQueue.removeFirst();
          _postAiMessage(q.text, key: q.key);
        } else {
          _phase = _Phase.recallSaved;
          await _askNext();
        }
      case _Phase.recallSaved:
        _postAiMessage(
          '証言を記録した。これからお聞きする出来事の報告書に、この内容も含めるか？',
          choices: ['はい', 'いいえ'],
        );
      case _Phase.modeSelect:
        _postAiMessage(
          '今日の事件簿を作成する。どうする？',
          choices: ['質問に沿って作成', '自分で入力'],
        );
      case _Phase.event:
        if (_eventQueue.isNotEmpty) {
          final q = _eventQueue.removeFirst();
          _postAiMessage(q.text, choices: q.choices, key: q.key);
        } else {
          _phase = _Phase.aiFollowUp;
          await _askAiFollowUp();
        }
      case _Phase.aiFollowUp:
        break; // _askAiFollowUp() から直接呼ぶため何もしない
      case _Phase.addendum:
        _postAiMessage(
          '他に言い残したことはあるか？',
          choices: ['はい(追記事項の入力へ)', 'いいえ(日記の生成へ)'],
        );
      case _Phase.diaryView:
        break; // 日記生成後はUIで操作するため何もしない
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
    _scrollToBottom();
  }

  // ユーザーの返答を受け取り、現在のフェーズに応じて次のアクションを決める
  Future<void> _sendUserReply(String text) async {
    if (text.trim().isEmpty) return;
    _textController.clear();
    setState(() => _currentChoices = null); // 選択肢を閉じる

    // 「その他(自由記述)」「カスタム」選択時はフリーテキスト入力に切り替える（回答はまだ記録しない）
    if ((text == 'その他(自由記述)' || text == 'カスタム') && _pendingKey != null) {
      await _firestore.saveMessage(
          _uid!, _today!, 'user', text, _conversationOrder++);
      setState(() => _messages.add({'role': 'user', 'text': text}));
      _postAiMessage('具体的に教えてください。', key: _pendingKey);
      return;
    }

    // 直前の質問にキーがあれば回答をanswersマップに記録する
    if (_pendingKey != null) {
      _answers[_pendingKey!] = text;
      if (_pendingKey == 'sleep') {
        final hours = _parseSleepHours(text);
        if (hours != null) _numericAnswers['sleep'] = hours;
      }
      _pendingKey = null;
    }

    await _firestore.saveMessage(
        _uid!, _today!, 'user', text, _conversationOrder++);
    setState(() => _messages.add({'role': 'user', 'text': text}));
    _scrollToBottom();

    switch (_phase) {
      case _Phase.custom:
        await _askNext();
      case _Phase.customSaved:
        _includeCustomInDiary = (text == 'はい');
        _phase = _Phase.recall;
        await _askNext();
      case _Phase.recall:
        await _askNext();
      case _Phase.recallSaved:
        _includeRecallInDiary = (text == 'はい');
        _phase = _Phase.modeSelect;
        await _askNext();
      case _Phase.modeSelect:
        if (text == '質問に沿って作成') {
          _phase = _Phase.event;
          _eventMsgStart = _messages.length;
          _postAiMessage(
            '今日の核心となる出来事について話を聞こう。何か思い当たる節はあるか？',
            choices: ['次へ'],
          );
        } else {
          // 「自分で入力」→ テキスト編集ページへ
          // 追記モードの場合は既存日記を初期値として渡す
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DiaryEditPage(
                  uid: _uid!,
                  today: _today!,
                  firestore: _firestore,
                  initialDiary: _existingDiary,
                ),
              ),
            );
          }
        }
      case _Phase.event:
        await _askNext();
      case _Phase.aiFollowUp:
        _phase = _Phase.addendum;
        await _askNext();
      case _Phase.addendum:
        if (text == 'はい(追記事項の入力へ)') {
          // 自由記述の追記入力へ（回答をaddendum_textキーで記録）
          _postAiMessage('言い残したことを話してくれ。', key: 'addendum');
        } else if (text == 'いいえ(日記の生成へ)') {
          // 追記なしで日記生成へ
          _phase = _Phase.diaryView;
          await _generateDiary();
        } else {
          // 'はい'選択後の自由記述入力 → answers['addendum']は保存済み
          _phase = _Phase.diaryView;
          await _generateDiary();
        }
      case _Phase.diaryView:
        break; // diaryViewフェーズはボタンで操作するため入力は無視
      case _Phase.done:
        break;
    }
  }

  // Geminiに追加質問を生成させる（AIフェーズで1回呼ばれる）
  // Geminiが「DONE」を返した場合はフォローアップをスキップしてaddendumへ進む
  Future<void> _askAiFollowUp() async {
    setState(() => _isLoading = true);
    try {
      final followUp = await _gemini.generateFollowUp(_messages);
      if (followUp == null) {
        // 証言十分と判断されたためフォローアップをスキップ
        _phase = _Phase.addendum;
        await _askNext();
        return;
      }
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

  // 日記生成後の4択ボタン（これを記録/編集する/生成しなおす/はじめから）を処理する
  Future<void> _handleDiaryViewChoice(String choice) async {
    switch (choice) {
      case 'これを記録':
        // 日記はすでに_generateDiary()で保存済み。完了メッセージを投稿してdoneへ
        setState(() => _phase = _Phase.done);
        _postAiMessage(
            '以上だ。事件簿はアーカイブに保管した。');
      case '編集する':
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DiaryEditPage(
                uid: _uid!,
                today: _today!,
                firestore: _firestore,
                initialDiary: _diary,
              ),
            ),
          );
        }
      case '生成しなおす':
        setState(() => _diary = null);
        await _generateDiary();
      case 'はじめから質問をやりなおす':
        // eventフェーズ以前のメッセージを保持し、それ以降をリセット
        setState(() {
          _messages.removeRange(_eventMsgStart, _messages.length);
          _diary = null;
          _diaryGenerated = false;
          _pendingKey = null;
          _currentChoices = null;
          _phase = _Phase.event;
        });
        // event関連の回答をクリアしてキューを再構築
        _answers.removeWhere((k, _) =>
            k.startsWith('event_') || k == 'ai_followup' || k == 'addendum');
        _eventQueue.clear();
        for (final q in _eventQuestions) {
          _eventQueue.add(q);
        }
        _postAiMessage(
          '今日の核心となる出来事について話を聞こう。何か思い当たる節はあるか？',
          choices: ['次へ'],
        );
    }
  }

  // カスタム・思い出しアシストのincludeフラグを考慮してGeminiに渡す追加コンテキストを生成する
  String _buildAdditionalContext() {
    final lines = <String>[];
    final customKeys = ['sleep', 'food', 'exercise', 'study'];
    if (_includeCustomInDiary) {
      for (final k in customKeys) {
        if (_answers.containsKey(k)) lines.add('$k: ${_answers[k]}');
      }
      _answers.keys.where((k) => k.startsWith('custom_')).forEach((k) {
        lines.add('カスタム: ${_answers[k]}');
      });
    }
    if (_includeRecallInDiary) {
      for (final k in ['morning', 'afternoon', 'evening']) {
        if (_answers.containsKey(k)) lines.add('$k: ${_answers[k]}');
      }
    }
    return lines.join('\n');
  }

  // 会話履歴からGeminiに日記を生成させてFirestoreに保存する
  Future<void> _generateDiary() async {
    setState(() {
      _phase = _Phase.diaryView;
      _isLoading = true;
    });
    try {
      // eventフェーズ以降のメッセージ＋オプションの追加コンテキストで日記を生成する
      final eventMessages = _messages.sublist(_eventMsgStart);
      final additionalContext = _buildAdditionalContext();
      final diary = _existingDiary != null
          ? await _gemini.generateDiaryWithExisting(
              _existingDiary!, eventMessages,
              additionalContext: additionalContext)
          : await _gemini.generateDiary(eventMessages,
              additionalContext: additionalContext);
      await Future.wait([
        _firestore.saveDiary(_uid!, _today!, diary),
        _firestore.saveAnswers(_uid!, _today!, _answers,
            numericAnswers: _numericAnswers),
      ]);
      _postAiMessage('事件簿を作成した。確認してくれ。');
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

  // 選択肢が多い場合のドロップダウンUI
  // 注意: 引数 `choices` はロジック上の選択肢リスト。色トークンを表す `c` と
  // 名前衝突しないよう変数名に注意する。
  Widget _buildDropdown(List<String> choices) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: c.appBarBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.gold.withValues(alpha: 0.5)),
      ),
      child: DropdownButton<String>(
        value: null,
        hint: Text('選択してください',
            style: TextStyle(color: c.appBarSubtitle)),
        isExpanded: true,
        underline: const SizedBox.shrink(),
        dropdownColor: c.appBarBg,
        style: TextStyle(color: c.appBarFg),
        items: choices
            .map((choice) => DropdownMenuItem(value: choice, child: Text(choice)))
            .toList(),
        onChanged: (val) {
          if (val != null) _sendUserReply(val);
        },
      ),
    );
  }

  // 選択肢が少ない場合のボタンUI
  Widget _buildChoiceButtons(List<String> choices) {
    final c = context.colors;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: choices.map((choice) {
        return ElevatedButton(
          onPressed: () => _sendUserReply(choice),
          style: ElevatedButton.styleFrom(
            backgroundColor: c.gold,
            foregroundColor: c.appBarFg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          child: Text(choice),
        );
      }).toList(),
    );
  }

  // 睡眠時間の文字列を時間数（double）にパースする
  // 例: "7時間" → 7.0 / "7.5時間" → 7.5 / "〜4時間" → 4.0 / "13時間〜" → 13.0
  // 数値が取れない場合は null を返す
  double? _parseSleepHours(String text) {
    if (text == '〜4時間') return 4.0;
    if (text == '13時間〜') return 13.0;
    final match = RegExp(r'(\d+(?:\.\d+)?)時間').firstMatch(text);
    if (match != null) return double.tryParse(match.group(1)!);
    return double.tryParse(text);
  }

  // メッセージ追加後にリストを最下端へスクロールする
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
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
        _phase != _Phase.diaryView &&
        _phase != _Phase.done;
    // diaryView・done・選択肢表示中はテキスト入力を非表示にする
    final showInput = !_diaryGenerated &&
        !_isLoading &&
        lastIsAI &&
        _currentChoices == null &&
        _phase != _Phase.diaryView &&
        _phase != _Phase.done;

    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,

      // ── AppBar ──────────────────────────────────────────────
      // 設定ページ・ホームと同じくサブタイトル付きで捜査中の雰囲気を演出する
      appBar: AppBar(
        backgroundColor: c.appBarBg,
        foregroundColor: c.appBarFg,
        elevation: 0,
        toolbarHeight: 64,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('新規捜査',
                style: DetectiveTextStyles.appBarTitle(color: c.appBarFg)),
            const SizedBox(height: 2),
            Text('― 証拠を集める ―',
                style: DetectiveTextStyles.appBarSubtitle(
                    color: c.appBarSubtitle)),
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
              controller: _scrollController,
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
            Padding(
              padding: const EdgeInsets.all(12.0),
              // ゴールドのローディングインジケーターでテーマに統一する
              child: CircularProgressIndicator(color: c.gold),
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
                          backgroundColor: c.bubbleUser,
                          foregroundColor: c.textPrimary,
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
          // 選択肢（5択以上はドロップダウン、4択以下はボタン）
          if (!_showExistingDiaryChoice && showChoices)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: _currentChoices!.length > 2
                  ? _buildDropdown(_currentChoices!)
                  : _buildChoiceButtons(_currentChoices!),
            ),
          // 既存日記を「確認する」で表示中の「編集する」ボタン
          if (_viewingExisting && _diaryGenerated && !_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: c.gold,
                          side: BorderSide(color: c.gold),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                        ),
                        child: const Text('閉じる'),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ElevatedButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DiaryEditPage(
                              uid: _uid!,
                              today: _today!,
                              firestore: _firestore,
                              initialDiary: _diary,
                            ),
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: c.gold,
                          foregroundColor: c.appBarFg,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                        ),
                        child: const Text('編集する'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // 日記確認フェーズの4択ボタン
          if (_phase == _Phase.diaryView && _diaryGenerated && !_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 上段: これを記録 / 編集する
                  Row(
                    children: ['これを記録', '編集する'].map((label) {
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ElevatedButton(
                            onPressed: () => _handleDiaryViewChoice(label),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: label == 'これを記録'
                                  ? c.gold
                                  : c.bubbleUser,
                              foregroundColor: label == 'これを記録'
                                  ? c.appBarFg
                                  : c.textPrimary,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                            child: Text(label),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  // 下段: 生成しなおす / はじめから
                  Row(
                    children: ['生成しなおす', 'はじめから質問をやりなおす'].map((label) {
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: OutlinedButton(
                            onPressed: () => _handleDiaryViewChoice(label),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: c.gold,
                              side: BorderSide(color: c.gold, width: 1),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                            child: Text(label,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 12)),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          // 記録完了後のナビゲーションボタン（ホームへ / 事件簿アーカイブへ）
          if (_phase == _Phase.done && !_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: c.gold,
                          side: BorderSide(color: c.gold, width: 1),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: const Text('ホームへ'),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ElevatedButton(
                        onPressed: () {
                          if (_uid == null) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DiaryListPage(uid: _uid!),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: c.gold,
                          foregroundColor: c.appBarFg,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: const Text('事件簿アーカイブへ'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (!_showExistingDiaryChoice && showInput)
            InputArea(controller: _textController, onSubmit: _sendUserReply),
        ],
      ),
    );
  }
}
