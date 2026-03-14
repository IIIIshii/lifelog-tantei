import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/user_settings.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/gemini_service.dart';

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

// 日記セッションのビジネスロジックを管理するコントローラ
// UIから切り離し、フェーズ遷移・AI呼び出し・Firestore保存の責務を担う
class DiarySessionController extends ChangeNotifier {
  late final GeminiService _gemini;
  final AuthService _auth = AuthService();
  final FirestoreService _firestore = FirestoreService();

  String? _uid;
  String? _today;
  int _conversationOrder = 0;
  final List<Map<String, String>> _messages = [];
  String? _diary;
  String? _existingDiary;
  int _addendumStartIndex = 0;
  bool _isLoading = false;
  bool _diaryGenerated = false;
  bool _showExistingDiaryChoice = false;
  List<String>? _currentChoices;
  String? _pendingKey;
  final Map<String, String> _answers = {};
  String? _lastError;

  _Phase _phase = _Phase.fixed;
  final Queue<_Question> _fixedQueue = Queue();
  final Queue<_Question> _eventQueue = Queue();
  final Queue<_Question> _customQueue = Queue();

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

  // ── Public getters (UI が読み取る状態) ──────────────────────────

  String? get uid => _uid;
  bool get isLoading => _isLoading;
  bool get diaryGenerated => _diaryGenerated;
  bool get showExistingDiaryChoice => _showExistingDiaryChoice;
  List<Map<String, String>> get messages => List.unmodifiable(_messages);
  String? get diary => _diary;
  String? get lastError => _lastError;
  List<String>? get currentChoices =>
      _currentChoices != null ? List.unmodifiable(_currentChoices!) : null;

  // UI の表示条件を計算するプロパティ（UIにフェーズ詳細を漏らさない）
  bool get showChoices {
    final lastIsAI = _messages.isNotEmpty && _messages.last['role'] == 'ai';
    return !_diaryGenerated &&
        !_isLoading &&
        lastIsAI &&
        _currentChoices != null &&
        _phase != _Phase.confirm &&
        _phase != _Phase.done;
  }

  bool get showInput {
    final lastIsAI = _messages.isNotEmpty && _messages.last['role'] == 'ai';
    return !_diaryGenerated &&
        !_isLoading &&
        lastIsAI &&
        _currentChoices == null &&
        _phase != _Phase.confirm &&
        _phase != _Phase.done;
  }

  bool get showConfirmButton => _phase == _Phase.confirm && !_isLoading;

  // ── 初期化 ──────────────────────────────────────────────────────

  DiarySessionController() {
    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    _gemini = GeminiService(apiKey);
  }

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();
    try {
      _uid = await _auth.signInAnonymously();
      _today = DateTime.now().toIso8601String().split('T')[0];

      final existingDiary = await _firestore.getTodayDiary(_uid!, _today!);
      if (existingDiary != null) {
        _conversationOrder = await _firestore.getMessageCount(_uid!, _today!);
        const message = '今日の事件簿がすでにあります。どうしますか？';
        await _firestore.saveMessage(
            _uid!, _today!, 'ai', message, _conversationOrder++);
        _existingDiary = existingDiary;
        _messages.add({'role': 'ai', 'text': message});
        _showExistingDiaryChoice = true;
        return;
      }

      final settings = await _firestore.getUserSettings(_uid!);
      _buildQueues(settings);
      await _askNext();
    } catch (e) {
      _setError('初期化エラー: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ── 既存日記の選択肢処理 ─────────────────────────────────────────

  Future<void> handleExistingDiaryChoice(String choice) async {
    await _firestore.saveMessage(
        _uid!, _today!, 'user', choice, _conversationOrder++);
    _showExistingDiaryChoice = false;
    _messages.add({'role': 'user', 'text': choice});
    notifyListeners();

    if (choice == '日記を確認する') {
      _diary = _existingDiary;
      _diaryGenerated = true;
      notifyListeners();
      return;
    }

    // 追記する → インタビュー開始インデックスを記録してから質問フローを開始
    _addendumStartIndex = _messages.length;
    _isLoading = true;
    notifyListeners();
    try {
      final settings = await _firestore.getUserSettings(_uid!);
      _buildQueues(settings);
      await _askNext();
    } catch (e) {
      _setError('初期化エラー: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ── 質問キュー構築 ───────────────────────────────────────────────

  void _buildQueues(UserSettings settings) {
    if (settings.recallAssist) {
      _fixedQueue.addAll([
        const _Question('午前中は何をしていましたか？', key: 'morning'),
        const _Question('午後は何をしていましたか？', key: 'afternoon'),
        const _Question('夜は何をしていましたか？', key: 'evening'),
      ]);
    }
    if (settings.recordSleep) {
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
      _fixedQueue.add(const _Question(
        '今日、筋トレをしましたか？',
        choices: ['はい', 'いいえ'],
        key: 'exercise',
      ));
    }
    if (settings.recordStudy) {
      _fixedQueue.add(const _Question('今日の勉強内容を教えてください。', key: 'study'));
    }

    _eventQueue.add(const _Question('記録したい出来事についてお聞きします。'));
    for (var i = 0; i < _eventQuestions.length; i++) {
      _eventQueue.add(_Question(_eventQuestions[i], key: _eventQuestionKeys[i]));
    }

    for (var i = 0; i < settings.customQuestions.length; i++) {
      _customQueue.add(_Question(settings.customQuestions[i], key: 'custom_$i'));
    }
  }

  // ── フェーズ管理 ─────────────────────────────────────────────────

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
        break; // AIフェーズは _askAiFollowUp() で直接呼ぶため _askNext() では何もしない
      case _Phase.confirm:
        _postAiMessage('以上で質問は終わりです。この内容で日記を生成しますか？');
      case _Phase.done:
        break;
    }
  }

  // Geminiを呼ばずにメッセージをAI発言としてリストとFirestoreに追加する
  void _postAiMessage(String text, {List<String>? choices, String? key}) {
    _firestore.saveMessage(_uid!, _today!, 'ai', text, _conversationOrder++);
    _messages.add({'role': 'ai', 'text': text});
    _currentChoices = choices;
    _pendingKey = key;
    notifyListeners();
  }

  // ユーザーの返答を受け取り、現在のフェーズに応じて次のアクションを決める
  Future<void> sendUserReply(String text) async {
    if (text.trim().isEmpty) return;

    if (_pendingKey != null) {
      _answers[_pendingKey!] = text;
      _pendingKey = null;
    }

    _currentChoices = null;
    await _firestore.saveMessage(
        _uid!, _today!, 'user', text, _conversationOrder++);
    _messages.add({'role': 'user', 'text': text});
    notifyListeners();

    switch (_phase) {
      case _Phase.fixed:
        await _askNext();
      case _Phase.eventQuestions:
        await _askNext();
      case _Phase.ai:
        _phase = _Phase.addendum;
        await _askNext();
      case _Phase.addendum:
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
    _isLoading = true;
    notifyListeners();
    try {
      final followUp = await _gemini.generateFollowUp(_messages);
      await _firestore.saveMessage(
          _uid!, _today!, 'ai', followUp, _conversationOrder++);
      _messages.add({'role': 'ai', 'text': followUp});
      _pendingKey = 'ai_followup';
      notifyListeners();
    } catch (e) {
      _setError('AIエラー: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 会話履歴全体からGeminiに日記を生成させてFirestoreに保存する
  Future<void> generateDiary() async {
    _phase = _Phase.done;
    _isLoading = true;
    notifyListeners();
    try {
      final diary = _existingDiary != null
          ? await _gemini.generateDiaryWithExisting(
              _existingDiary!, _messages.sublist(_addendumStartIndex))
          : await _gemini.generateDiary(_messages);
      await Future.wait([
        _firestore.saveDiary(_uid!, _today!, diary),
        _firestore.saveAnswers(_uid!, _today!, _answers),
      ]);
      _diary = diary;
      _diaryGenerated = true;
      notifyListeners();
    } catch (e) {
      _setError('日記生成エラー: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ── エラー ───────────────────────────────────────────────────────

  void _setError(String message) {
    _lastError = message;
    notifyListeners();
  }

  void clearError() {
    _lastError = null;
  }
}
