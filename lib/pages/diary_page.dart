import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../core/daily_record.dart';
import '../core/goal_digest.dart';
import '../core/scroll.dart';
import '../core/streak.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/detective_text_styles.dart';
import '../models/goal.dart';
import '../roles/roles.dart';
import '../services/firestore_service.dart';
import '../services/gemini_service.dart';
import '../widgets/choice_buttons.dart';
import '../widgets/diary_card.dart';
import '../widgets/input_area.dart';
import '../widgets/message_bubble.dart';
import 'diary_edit_page.dart';
import 'record_sheet_page.dart';

// 聴取（日記の作成）。
//
// 「出来事を選ぶ → その出来事を深掘りする」を何度でも繰り返し、最後に
// その日1件の日記本文へまとめる。睡眠時間や何をしたかといった事実は
// 日々の記録（RecordSheetPage）が受け持つので、ここでは聞かない。
// 記録があれば読み込み、話題の候補出しと日記の材料に使う。
//
// 以前の DiaryPage は固定質問・思い出しアシスト・出来事の5問・深掘り・追記を
// 1本の12状態のステートマシンで抱えていた。事実の確認を表へ切り出したことで、
// ここは「選ぶ → 掘る → まとめる」だけになった。
//
// 保存:
//   diaries/{date}            text / topics / role / mode
//   diaries/{date}/interview  会話（発言ごとに、どの出来事の話かを topic で残す）
enum _Phase {
  loading,
  existingChoice, // 既に日記がある日：足すか、作り直すか、直すか
  topicSelect, // 次に話す出来事を選んでいる
  topicInput, // 候補に無い出来事を自分で書いている
  interviewing, // 1つの出来事を深掘りしている
  review, // 日記をまとめた。確認している
  done,
}

// 画面に出す1行。role は 'ai' / 'user' / 'diary'（日記本文のカード）。
class _Line {
  final String role;
  final String text;

  /// どの出来事についての発言か。出来事の選択などのやりとりは null。
  final String? topic;

  /// 非 null なら、この行の下に選択肢ボタンを出す
  final List<String>? choices;

  const _Line({
    required this.role,
    required this.text,
    this.topic,
    this.choices,
  });
}

// 既に日記がある日の選択肢
const _kAddTopics = '出来事を足して書き直す';
const _kRestart = 'いちから作り直す';
const _kEditByHand = '手で直す';
const _kReadDiary = '日記を読む';

// 出来事を選ぶときの選択肢（候補の後ろに付ける）
const _kOtherTopic = '別の出来事を話す';
const _kWriteDiary = '日記にまとめる';

// AI が候補を出せず、記録にも手がかりが無いときの見出し
const _kGenericTopics = ['今日いちばん印象に残ったこと', '誰かとのやりとり', 'ちょっとした発見や変化'];

class DiaryPage extends StatefulWidget {
  /// 対象の日付（YYYY-MM-DD）。null なら今日。
  final String? date;

  const DiaryPage({super.key, this.date});

  @override
  State<DiaryPage> createState() => _DiaryPageState();
}

class _DiaryPageState extends State<DiaryPage> {
  final FirestoreService _firestore = FirestoreService();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _textController = TextEditingController();

  late final String _uid;
  late final String _date;
  GeminiService? _gemini;
  Role _role = roleFor(null);

  _Phase _phase = _Phase.loading;
  bool _busy = false; // Gemini の応答待ち・保存中
  int _order = 0; // 会話の通し番号（同じ日に何度聴取しても衝突しないよう続きから）
  int _animatedUpTo = 0; // タイプライター表示を流し終えた位置
  final List<_Line> _lines = [];

  // その日の記録。候補出しと最初の質問には全部、日記の本文には日記に使う項目だけを渡す。
  String _recordContext = '';
  String _diaryContext = '';
  // AI が候補を出せなかったときに、記録のテキスト項目から作る見出し
  List<String> _recordHints = const [];
  List<String> _recentDiaries = const [];
  // 追っている目標の直近の続き具合。質問が目標の実績を踏まえられるようにする。
  String _goalContext = '';

  // 話題の候補。最初に一度だけ出させ、選ばれたものから外していく
  // （出来事を1つ話すたびに候補を出し直すと、そのたびに待たされるため）。
  List<String> _candidates = const [];
  bool _candidatesLoaded = false;

  String? _existingText; // 出来事を足すときの、元の日記本文
  final List<String> _priorTopics = []; // 元の日記で話していた出来事
  final List<String> _topics = []; // この聴取で話した出来事
  String? _currentTopic;
  int _followUps = 0;
  String? _diary; // まとめた日記

  bool get _isRevisit => _date != dateKey(DateTime.now());

  @override
  void initState() {
    super.initState();
    // AuthGate により認証済みでのみ到達する
    _uid = FirebaseAuth.instance.currentUser!.uid;
    _date = widget.date ?? dateKey(DateTime.now());
    _init();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _textController.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────────
  // 読み込み
  // ──────────────────────────────────────────────────────────────

  Future<void> _init() async {
    try {
      final settingsFuture = _firestore.getUserSettings(_uid);
      final selfAnalysisFuture = _firestore.getSelfAnalysis(_uid);
      final diaryFuture = _firestore.getDiary(_uid, _date);
      final countFuture = _firestore.getInterviewCount(_uid, _date);
      final recentFuture = _firestore.getRecentDiaries(_uid, 8);
      final settings = await settingsFuture;
      final selfAnalysis = await selfAnalysisFuture;
      final diary = await diaryFuture;
      final count = await countFuture;
      final recent = await recentFuture;
      await _loadRecord();
      if (!mounted) return;

      _role = roleFor(settings.selectedRole);
      _gemini = GeminiService(
        dotenv.env['GEMINI_API_KEY'] ?? '',
        settings.selectedRole,
        selfAnalysis: selfAnalysis,
      );
      _order = count;
      // 記録が乏しい日の手がかりとして、直近の日記を数件だけ渡す（長いものは切る）
      _recentDiaries = [
        for (final entry
            in (recent.where((e) => e.key != _date).toList()
                  ..sort((a, b) => b.key.compareTo(a.key)))
                .take(3))
          _clip((entry.value['text'] as String?) ?? '', 120),
      ].where((text) => text.isNotEmpty).toList();

      setState(() => _phase = _Phase.topicSelect);

      if (_isRevisit) {
        _post(
          '対象は${_monthDay(_date)}。'
          '${_role.text('revisit_notice', '質問の「今日」は、その日のことだと思って答えてくれ。')}',
        );
      }

      final existing = (diary?['text'] as String?)?.trim() ?? '';
      if (existing.isNotEmpty) {
        _existingText = existing;
        _priorTopics.addAll(
          (diary?['topics'] as List<dynamic>?)?.whereType<String>() ??
              const [],
        );
        setState(() => _phase = _Phase.existingChoice);
        _post(
          _role.text('diary_exists', 'この日の事件簿はすでにある。どうする？'),
          choices: const [_kAddTopics, _kRestart, _kEditByHand, _kReadDiary],
        );
        return;
      }
      await _openTopicSelect();
    } catch (e) {
      if (!mounted) return;
      // 読み込み中のまま止めず、「閉じる」だけは押せるようにしておく
      setState(() {
        _busy = false;
        _phase = _Phase.done;
      });
      _showError('聴取を始められなかった: $e');
    }
  }

  // その日の記録を読み、プロンプトに渡す要約を作り直す。
  // 聴取の途中で記録を開いて書き足したときにも呼ぶ。
  Future<void> _loadRecord() async {
    final fieldsFuture = _firestore.getFields(_uid);
    final goalsFuture = _firestore.getGoals(_uid);
    final recordFuture = _firestore.getRecord(_uid, _date);
    final fields = await fieldsFuture;
    final goals = await goalsFuture;
    final record = await recordFuture;
    final day = DateTime.tryParse(_date) ?? DateTime.now();
    final rows = fieldsForDay(fields, goals, day);
    _recordContext = recordSummary(rows, record);
    _diaryContext = recordSummary(rows, record, diaryOnly: true);
    _recordHints = topicHintsFromRecord(rows, record);
    await _loadGoalContext(goals);
  }

  // 目標の続き具合を読む。質問の補助でしかないので、失敗しても聴取は止めない。
  Future<void> _loadGoalContext(List<Goal> goals) async {
    try {
      final recent = await _firestore.getRecentRecords(_uid, 14);
      _goalContext = activeGoalsDigest(goals, recent, DateTime.now());
    } catch (e) {
      debugPrint('目標の続き具合を読めなかった: $e');
      _goalContext = '';
    }
  }

  // ──────────────────────────────────────────────────────────────
  // 会話の出し入れ
  // ──────────────────────────────────────────────────────────────

  void _post(String text, {String? topic, List<String>? choices}) {
    setState(() {
      _lines.add(
        _Line(role: 'ai', text: text, topic: topic, choices: choices),
      );
    });
    _save('ai', text, topic);
    scrollToBottom(_scrollController);
  }

  void _postUser(String text, {String? topic}) {
    setState(() => _lines.add(_Line(role: 'user', text: text, topic: topic)));
    _save('user', text, topic);
    scrollToBottom(_scrollController);
  }

  // 発言を残す。待たないのは、書き込みのたびに次の問いが止まると間が空くため。
  // 1通残らなくても日記そのものは saveDiary で残るので、画面は止めない。
  void _save(String role, String text, String? topic) {
    _firestore
        .saveInterviewMessage(
          _uid,
          _date,
          role: role,
          text: text,
          order: _order++,
          topic: topic,
        )
        .catchError((Object e) => debugPrint('会話の保存に失敗しました: $e'));
  }

  // 日記の材料にする会話。出来事ごとに「話したい出来事: ○○」を頭に置いて並べる。
  // onlyTopic を渡すとその出来事の分だけ（深掘りの判断に使う）。
  List<Map<String, String>> _interviewMessages({String? onlyTopic}) {
    final topics = onlyTopic == null ? _topics : [onlyTopic];
    return [
      for (final topic in topics) ...[
        {'role': 'user', 'text': '話したい出来事: $topic'},
        for (final line in _lines)
          if (line.topic == topic && line.role != 'diary')
            {'role': line.role, 'text': line.text},
      ],
    ];
  }

  // ──────────────────────────────────────────────────────────────
  // 流れ
  // ──────────────────────────────────────────────────────────────

  // 既に日記がある日の選択
  Future<void> _onExistingChoice(String choice) async {
    switch (choice) {
      case _kReadDiary:
        // 本文を見せ、同じ選択肢を本文の下に出し直す（読むのは何度でもよいので外す）
        setState(() {
          _lines.add(
            _Line(
              role: 'diary',
              text: _existingText ?? '',
              choices: const [_kAddTopics, _kRestart, _kEditByHand],
            ),
          );
        });
        scrollToBottom(_scrollController);
      case _kEditByHand:
        await _writeByHand();
      case _kRestart:
        _postUser(choice);
        // 元の本文を材料に渡さず、今回の聴取だけで書き直す
        _existingText = null;
        _priorTopics.clear();
        await _openTopicSelect();
      case _kAddTopics:
        _postUser(choice);
        await _openTopicSelect();
    }
  }

  // 次に話す出来事を選ばせる
  Future<void> _openTopicSelect() async {
    setState(() {
      _phase = _Phase.topicSelect;
      _currentTopic = null;
    });
    if (!_candidatesLoaded) {
      setState(() => _busy = true);
      var candidates = <String>[];
      try {
        candidates = await _gemini!.generateTopicCandidates(
          recordContext: _recordContext,
          recentDiaries: _recentDiaries,
          coveredTopics: [..._priorTopics, ..._topics],
        );
      } catch (e) {
        debugPrint('話題の候補を出せませんでした: $e');
      }
      if (!mounted) return;
      if (candidates.isEmpty) candidates = [..._recordHints];
      if (candidates.isEmpty) candidates = [..._kGenericTopics];
      // 既に話した出来事と、操作用のボタンと同じ文言は候補から外す
      // （AI には外すよう指示しているが、守られる保証は無い）
      final excluded = {
        ..._priorTopics,
        ..._topics,
        _kOtherTopic,
        _kWriteDiary,
      };
      setState(() {
        _candidates = candidates
            .where((c) => !excluded.contains(c))
            .toSet()
            .take(4)
            .toList();
        _candidatesLoaded = true;
        _busy = false;
      });
    }

    final first = _topics.isEmpty;
    _post(
      first
          ? _role.text('intro_topics', '今日の事件簿を作る。どの件から話す？')
          : _role.text('topic_more', '他に記録しておく件はあるか？'),
      choices: [
        ..._candidates,
        _kOtherTopic,
        if (!first) _kWriteDiary,
      ],
    );
  }

  Future<void> _onTopicChoice(String choice) async {
    _postUser(choice);
    switch (choice) {
      case _kOtherTopic:
        setState(() => _phase = _Phase.topicInput);
        _post(_role.text('topic_custom', 'どんな出来事だ？ ひとことで言ってくれ。'));
      case _kWriteDiary:
        await _generate();
      default:
        await _startTopic(choice);
    }
  }

  // 出来事の深掘りを始める。最初の問いは AI に作らせる。
  Future<void> _startTopic(String topic) async {
    setState(() {
      _candidates = _candidates.where((c) => c != topic).toList();
      if (!_topics.contains(topic)) _topics.add(topic);
      _currentTopic = topic;
      _followUps = 0;
      _phase = _Phase.interviewing;
      _busy = true;
    });
    var question = '';
    try {
      question = await _gemini!.generateTopicQuestion(
        topic: topic,
        recordContext: _recordContext,
        goalContext: _goalContext,
      );
    } catch (e) {
      debugPrint('最初の質問を作れませんでした: $e');
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _post(
      question.isNotEmpty
          ? question
          : _role.text('topic_question_fallback', 'そのとき、どんな場面だった？'),
      topic: topic,
    );
  }

  // 入力欄からの送信。出来事を書いているのか、深掘りに答えているのかで分ける。
  Future<void> _onSubmit(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _textController.clear();

    if (_phase == _Phase.topicInput) {
      _postUser(trimmed);
      await _startTopic(trimmed);
      return;
    }
    final topic = _currentTopic;
    if (_phase != _Phase.interviewing || topic == null) return;
    _postUser(trimmed, topic: topic);
    await _askFollowUp(topic);
  }

  // 深掘りを続けるか決める。ロールの回数に達したか、十分に語られたら次の出来事へ。
  Future<void> _askFollowUp(String topic) async {
    if (_followUps >= _role.followUpCount) {
      await _closeTopic();
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await _gemini!.generateFollowUp(
        _interviewMessages(onlyTopic: topic),
        recordContext: _recordContext,
        goalContext: _goalContext,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      if (result.sufficient) {
        await _closeTopic();
        return;
      }
      _followUps++;
      _post(result.question, topic: topic);
    } catch (e) {
      // 深掘りが失敗しても、話した分は残っている。止めずに次の出来事へ進める
      debugPrint('深掘りの質問を作れませんでした: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      await _closeTopic();
    }
  }

  Future<void> _closeTopic() async {
    _post(_role.text('topic_close', 'この件は押さえた。'));
    await _openTopicSelect();
  }

  // 話した出来事をまとめて日記にする。
  Future<void> _generate() async {
    if (_topics.isEmpty) return;
    setState(() {
      _phase = _Phase.review;
      _busy = true;
    });
    try {
      final messages = _interviewMessages();
      final existing = _existingText;
      final text = existing != null
          ? await _gemini!.generateDiaryWithExisting(
              existing,
              messages,
              recordContext: _diaryContext,
            )
          : await _gemini!.generateDiary(
              messages,
              recordContext: _diaryContext,
            );
      await _firestore.saveDiary(
        _uid,
        _date,
        text: text,
        topics: [..._priorTopics, ..._topics],
        role: _role.key,
        mode: 'interview',
      );
      if (!mounted) return;
      setState(() {
        _diary = text;
        _busy = false;
      });
      _post(_role.text('diary_generated', '事件簿をまとめた。確認してくれ。'));
      setState(() => _lines.add(_Line(role: 'diary', text: text)));
      scrollToBottom(_scrollController);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        // まとめられなかったら出来事の選択へ戻し、もう一度押せるようにする
        _phase = _Phase.topicSelect;
      });
      _showError('日記をまとめられなかった: $e');
      await _openTopicSelect();
    }
  }

  Future<void> _editGenerated() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => DiaryEditPage(
          uid: _uid,
          date: _date,
          firestore: _firestore,
          initialDiary: _diary,
        ),
      ),
    );
    if (!mounted) return;
    // 手で直した本文を画面にも反映する
    final latest = await _firestore.getDiaryText(_uid, _date);
    if (!mounted || latest == null || latest == _diary) return;
    setState(() {
      _diary = latest;
      _lines.add(_Line(role: 'diary', text: latest));
    });
    scrollToBottom(_scrollController);
  }

  void _finish() {
    setState(() => _phase = _Phase.done);
    _post(_role.text('diary_done', '以上だ。事件簿は綴じておいた。'));
  }

  // 聴取の途中でその日の記録を開く。戻ったら要約を作り直す
  // （出来事の候補は出し直さない。話の途中で候補が入れ替わると混乱するため）。
  Future<void> _openRecordSheet() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => RecordSheetPage(uid: _uid, date: _date),
      ),
    );
    if (!mounted) return;
    try {
      await _loadRecord();
    } catch (e) {
      debugPrint('記録を読み直せませんでした: $e');
    }
  }

  // 探偵に聞かれずに手で書く（既に日記がある日は、その本文を直す）。
  // 保存して戻ってきたら聴取は要らないので、この画面も閉じる。
  // 保存せずに戻ってきたときは聴取を続けられるよう残す。
  Future<void> _writeByHand() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => DiaryEditPage(
          uid: _uid,
          date: _date,
          firestore: _firestore,
          initialDiary: _existingText,
        ),
      ),
    );
    if (saved == true && mounted) Navigator.pop(context);
  }

  // ──────────────────────────────────────────────────────────────
  // 表示
  // ──────────────────────────────────────────────────────────────

  String _monthDay(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return key;
    return '${int.tryParse(parts[1]) ?? parts[1]}月${int.tryParse(parts[2]) ?? parts[2]}日';
  }

  static String _clip(String text, int max) {
    final trimmed = text.trim();
    return trimmed.length > max ? '${trimmed.substring(0, max)}…' : trimmed;
  }

  void _showError(String message) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('エラー'),
        content: SelectableText(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    // タイプ中の吹き出しは1件だけ。流し終えるまでは答えさせない
    // （読み終える前に選択肢が出ると急かされて見えるため）
    int? typingIndex;
    for (var i = _animatedUpTo; i < _lines.length; i++) {
      if (_lines[i].role == 'ai') {
        typingIndex = i;
        break;
      }
    }
    final last = _lines.isEmpty ? null : _lines.last;
    final ready = !_busy && typingIndex == null;
    final choices = last?.role != 'user' ? last?.choices : null;
    final showChoices = ready && choices != null;
    final waitingAnswer =
        ready &&
        last?.role == 'ai' &&
        (_phase == _Phase.topicInput || _phase == _Phase.interviewing);

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.appBarBg,
        foregroundColor: c.appBarFg,
        elevation: 0,
        toolbarHeight: 64,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isRevisit ? '再捜査' : '聴取',
              style: DetectiveTextStyles.appBarTitle(color: c.appBarFg),
            ),
            const SizedBox(height: 2),
            Text(
              _isRevisit
                  ? '― ${_monthDay(_date)}の出来事を聞き直す ―'
                  : '― 出来事を掘り下げる ―',
              style: DetectiveTextStyles.appBarSubtitle(
                color: c.appBarSubtitle,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.fact_check_outlined),
            tooltip: 'この日の記録を開く',
            onPressed: _phase == _Phase.loading ? null : _openRecordSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_topics.isNotEmpty || _priorTopics.isNotEmpty)
            _TopicStrip(
              topics: [..._priorTopics, ..._topics],
              current: _currentTopic,
            ),
          Expanded(
            child: _phase == _Phase.loading
                ? Center(child: CircularProgressIndicator(color: c.gold))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _lines.length,
                    itemBuilder: (context, index) {
                      final line = _lines[index];
                      if (line.role == 'diary') {
                        return DiaryCard(diary: line.text);
                      }
                      return MessageBubble(
                        role: line.role,
                        text: line.text,
                        animate: index == typingIndex,
                        onAnimationFinished: () {
                          if (!mounted) return;
                          setState(() => _animatedUpTo = index + 1);
                          scrollToBottom(_scrollController);
                        },
                      );
                    },
                  ),
          ),
          if (_busy)
            Padding(
              padding: const EdgeInsets.all(12),
              child: CircularProgressIndicator(color: c.gold),
            ),
          if (showChoices)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: StackedChoiceButtons(
                choices: choices,
                onSelect: _phase == _Phase.existingChoice
                    ? _onExistingChoice
                    : _onTopicChoice,
              ),
            ),
          // 最初の出来事を選ぶ前だけ、探偵に聞かれずに自分で書く道を残す
          if (showChoices && _phase == _Phase.topicSelect && _topics.isEmpty)
            TextButton.icon(
              onPressed: _writeByHand,
              icon: Icon(Icons.edit_outlined, size: 16, color: c.gold),
              label: Text(
                '探偵に聞かれずに自分で書く',
                style: TextStyle(fontSize: 12, color: c.gold),
              ),
            ),
          if (waitingAnswer)
            InputArea(
              controller: _textController,
              onSubmit: _onSubmit,
              hintText: _phase == _Phase.topicInput ? '出来事をひとことで…' : '証言を入力...',
            ),
          if (waitingAnswer && _phase == _Phase.interviewing)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextButton.icon(
                onPressed: _closeTopic,
                icon: Icon(Icons.skip_next, size: 18, color: c.textSecondary),
                label: Text(
                  'この出来事はここまで',
                  style: TextStyle(color: c.textSecondary),
                ),
              ),
            ),
          if (_phase == _Phase.review && ready && _diary != null)
            _ReviewButtons(
              onAccept: _finish,
              onEdit: _editGenerated,
              onRegenerate: _generate,
              onAddTopic: _openTopicSelect,
            ),
          if (_phase == _Phase.done && ready)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.gold,
                    foregroundColor: c.onAccent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('閉じる'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// 話した出来事の帯。何件話したか、今どれを掘っているかを上に出しておく。
class _TopicStrip extends StatelessWidget {
  final List<String> topics;
  final String? current;

  const _TopicStrip({required this.topics, required this.current});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      color: c.cardBg,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Text(
              '出来事 ${topics.length}件',
              style: TextStyle(fontSize: 11, color: c.textSecondary),
            ),
            for (final topic in topics) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: topic == current ? c.goldLight : Colors.transparent,
                  border: Border.all(
                    color: topic == current ? c.gold : c.cardBorder,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(
                  topic,
                  style: TextStyle(
                    fontSize: 11,
                    color: topic == current ? c.caseNumberFg : c.textPrimary,
                    fontWeight: topic == current
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// 日記をまとめた後の操作。
class _ReviewButtons extends StatelessWidget {
  final VoidCallback onAccept;
  final VoidCallback onEdit;
  final VoidCallback onRegenerate;
  final VoidCallback onAddTopic;

  const _ReviewButtons({
    required this.onAccept,
    required this.onEdit,
    required this.onRegenerate,
    required this.onAddTopic,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final outlined = OutlinedButton.styleFrom(
      foregroundColor: c.gold,
      side: BorderSide(color: c.gold),
      padding: const EdgeInsets.symmetric(vertical: 12),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: onAccept,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.gold,
                    foregroundColor: c.onAccent,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('これで記録'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: onEdit,
                  style: outlined,
                  child: const Text('手で直す'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onAddTopic,
                  style: outlined,
                  child: const Text('出来事を足す', style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: onRegenerate,
                  style: outlined,
                  child: const Text('まとめ直す', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
