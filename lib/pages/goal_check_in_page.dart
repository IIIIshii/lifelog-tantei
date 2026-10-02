import 'package:flutter/material.dart';

import '../core/goal_progress.dart';
import '../core/numeric_answer.dart';
import '../core/scroll.dart';
import '../core/streak.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/detective_text_styles.dart';
import '../models/goal.dart';
import '../roles/roles.dart';
import '../services/firestore_service.dart';
import '../widgets/choice_buttons.dart';
import '../widgets/input_area.dart';
import '../widgets/message_bubble.dart';

// 追跡中の事件について、今日の報告を受ける画面。
// ホームの FAB から日記の新規捜査より先に開かれる。
//
// 日記（DiaryPage）と分けている理由:
// 日記と目標は別の記録で、保存先も users/{uid}/entries と
// users/{uid}/goals/{goalId}/entries に分かれている。以前は目標の質問を日記の
// 質問キューに相乗りさせていたが、1600行のステートマシンに別の関心事が混ざり、
// どちらを直しても他方が壊れうる状態になっていた。
//
// DiaryPage の12状態を持ち込まないのも同じ趣旨で、ここは
// 「前置き → 質問を順に聞く → 終わり」の一本道。分岐モードも日記生成も無い。
//
// Gemini は呼ばない。質問文は GoalAction.questionText()、前置きはロール定義から引く。
// 毎日必ず通る画面なので、応答待ちを挟まず即座に始められることを優先した
// （オフラインでも記録だけは残せる）。
enum _Phase {
  intro, // 前置きを出している
  asking, // 質問中
  done, // 全問終わった
}

class GoalCheckInPage extends StatefulWidget {
  final String uid;

  /// 対象の日付（YYYY-MM-DD）。省略すると今日。
  final String? date;

  const GoalCheckInPage({super.key, required this.uid, this.date});

  @override
  State<GoalCheckInPage> createState() => _GoalCheckInPageState();
}

class _GoalCheckInPageState extends State<GoalCheckInPage> {
  final FirestoreService _firestore = FirestoreService();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _textController = TextEditingController();

  Role _role = roleFor(null);
  late String _date;

  bool _initializing = true;
  bool _saving = false;
  _Phase _phase = _Phase.intro;

  // 画面に出す会話。目標ごとのログへ振り分けるため、どの目標の発言かを添えて持つ
  // （owner が null なら「どの目標にも属さない発言」＝前置きと締め）。
  final List<_Line> _lines = [];

  // この報告で聞く質問の列。目標をまたいで1本になっている（buildGoalQuestionQueue）
  List<({Goal goal, GoalAction action})> _queue = const [];
  int _cursor = 0;

  // 目標 id → 保存する回答。答え終わった目標のぶんから順に書き込む
  final Map<String, Map<String, String>> _answersByGoal = {};
  final Map<String, Map<String, double>> _numericByGoal = {};
  final Map<String, List<String>> _skippedByGoal = {};

  // 目標 id → 会話の order カウンタ。
  // 同じ日に2回目の報告をしても order が衝突しないよう、既存の件数から始める。
  final Map<String, int> _orderByGoal = {};

  int _animatedUpTo = 0; // タイプライター表示を流し終えた位置
  bool _numericRetried = false; // 今の質問で数字を聞き直したか（聞き直しは1回だけ）

  @override
  void initState() {
    super.initState();
    _date = widget.date ?? dateKey(DateTime.now());
    _init();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final settingsFuture = _firestore.getUserSettings(widget.uid);
      final goalsFuture = _firestore.getGoals(widget.uid);
      final settings = await settingsFuture;
      final goals = await goalsFuture;

      // 着手より前の日は聞かない（まだ追っていなかった日が達成率の母数に入るため）
      final tracked = goalsTrackedOn(goals, _date);
      final queue = buildGoalQuestionQueue(tracked);
      final ids = {for (final item in queue) item.goal.id};

      // 既に答えている目標と、会話 order の開始位置を同時に押さえる
      final existing = await _firestore.getGoalEntriesOn(
        widget.uid,
        ids,
        _date,
      );
      final counts = await Future.wait(
        ids.map(
          (id) async =>
              (id, await _firestore.getGoalMessageCount(widget.uid, id, _date)),
        ),
      );
      if (!mounted) return;

      final recorded = goalsRecordedIn(existing, tracked);

      setState(() {
        _role = roleFor(settings.selectedRole);
        _queue = queue;
        for (final entry in counts) {
          _orderByGoal[entry.$1] = entry.$2;
        }
        _initializing = false;
      });

      if (queue.isEmpty) {
        // 追跡中の事件が無い／質問を持つ事件が無い。ここで止めても行き先が無いので
        // 一言だけ置いて日記へ送る（FAB 側でも0件なら開かないが、着手日の絞り込みで
        // 質問が無くなる日もある）。
        _post(_role.text('goal_empty', '追うべき事件は、まだ決まっていない。'));
        setState(() => _phase = _Phase.done);
        return;
      }

      // 全部の事件を既に報告済みなら、聞き直すか日記へ進むかを選ばせる。
      // 黙って閉じないのは、この画面を経由して日記へ進む動線が壊れるため。
      if (recorded.length == ids.length) {
        _post(
          '${_role.text('goal_checkin_recorded', '今日の報告はもう受けている。')}'
          '聞き直すか、捜査へ進むか。',
          choices: const ['もう一度報告する', '捜査へ進む'],
        );
        return;
      }

      _post(_role.text('intro_goal_checkin', '追っている事件の報告を聞こう。'));
      _askNext();
    } catch (e) {
      if (!mounted) return;
      setState(() => _initializing = false);
      _showError('報告を始められなかった: $e');
    }
  }

  // 探偵の発言を会話へ足す。
  //
  // owner を渡すとその目標のログへだけ保存し、省くと「聞く対象の全事件」へ複製する。
  // 複製するのは、目標ごとのエントリが記録一覧から単体で読み返されるため
  // ―― 前置きが無いと、その日の会話が唐突に質問から始まって終わる。
  void _post(String text, {Goal? owner, List<String>? choices}) {
    setState(() {
      _lines.add(_Line(role: 'ai', text: text, owner: owner, choices: choices));
    });
    _saveMessage(text, 'ai', owner: owner);
    scrollToBottom(_scrollController);
  }

  void _postUser(String text, Goal owner) {
    setState(() {
      _lines.add(_Line(role: 'user', text: text, owner: owner));
    });
    _saveMessage(text, 'user', owner: owner);
    scrollToBottom(_scrollController);
  }

  // 会話ログを Firestore へ流す。
  // await しないのは、書き込みを待つ間に次の質問が止まると尋問の間が空くため
  // （DiaryPage も発言ごとに投げて待たない作り）。order は自前で進める。
  void _saveMessage(String text, String role, {Goal? owner}) {
    final targets = owner != null
        ? [owner.id]
        : {for (final item in _queue) item.goal.id}.toList();
    for (final id in targets) {
      final order = _orderByGoal[id] ?? 0;
      _orderByGoal[id] = order + 1;
      _firestore
          .saveGoalMessage(widget.uid, id, _date, role, text, order)
          // 会話が1通残らなくても報告そのものは saveGoalAnswers で残る。
          // ここで画面を止める価値は無いので、印だけ出して流す。
          .catchError((Object e) => debugPrint('会話の保存に失敗しました: $e'));
    }
  }

  // 次の質問を出す。列の終わりまで来たら締めて保存する。
  void _askNext() {
    if (_cursor >= _queue.length) {
      _finish();
      return;
    }
    final item = _queue[_cursor];
    // 事件が切り替わるところで、どの事件の話かを断る。
    // この発言はその目標のログにだけ入るので、読み返したときの導入文にもなる。
    final isFirstOfGoal =
        _cursor == 0 || _queue[_cursor - 1].goal.id != item.goal.id;
    if (isFirstOfGoal) {
      _post(
        '${_role.text('goal_checkin_switch', '次はこの事件だ。')} ―― ${item.goal.title}',
        owner: item.goal,
      );
    }
    _numericRetried = false;
    setState(() => _phase = _Phase.asking);
    _post(
      item.action.questionText(),
      owner: item.goal,
      // 達成／未達の2択はボタン、数値は自由入力で受ける
      choices: item.action.isNumeric ? null : const [kGoalDone, kGoalNotDone],
    );
  }

  // 回答を受け取る。選択肢ボタンとテキスト入力の両方からここへ来る。
  Future<void> _answer(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _textController.clear();

    // 前置きの2択（もう一度報告する／捜査へ進む）だけは質問の前に来る
    if (_phase == _Phase.intro) {
      if (trimmed == '捜査へ進む') {
        if (mounted) Navigator.pop(context, true);
        return;
      }
      setState(() => _lines.add(_Line(role: 'user', text: trimmed)));
      _post(_role.text('intro_goal_checkin', '追っている事件の報告を聞こう。'));
      _askNext();
      return;
    }

    final item = _queue[_cursor];
    _postUser(trimmed, item.goal);

    if (item.action.isNumeric) {
      final value = parseNumericAnswer(trimmed);
      if (value == null && !_numericRetried) {
        // 数字が拾えないと回答文字列だけが残り、分析室のグラフからは静かに消える。
        // 気づけない欠落なので、ここで一度だけ聞き直す。
        _numericRetried = true;
        _post(
          _role.text('goal_checkin_numeric_retry', '数字が拾えなかった。数字だけで頼む。'),
          owner: item.goal,
        );
        return;
      }
      if (value != null) {
        (_numericByGoal[item.goal.id] ??= {})[item.action.answerKey] = value;
      }
    }
    (_answersByGoal[item.goal.id] ??= {})[item.action.answerKey] = trimmed;

    await _advance();
  }

  // 今の質問を飛ばす。回答は入れず、スキップしたキーだけを残す
  // （checkRate は答えた日だけを母数にするので、達成率は下がらない）。
  Future<void> _skip() async {
    final item = _queue[_cursor];
    _postUser('（報告なし）', item.goal);
    (_skippedByGoal[item.goal.id] ??= []).add(item.action.answerKey);
    await _advance();
  }

  // 次の質問へ進む。事件が切り替わる手前で、答え終わった事件のぶんを保存する。
  //
  // 全問終わってから一度に書かないのは、3件のうち2件まで答えて離脱したときに
  // その2件を残せるようにするため。
  Future<void> _advance() async {
    final current = _queue[_cursor].goal;
    _cursor++;
    final isLastOfGoal =
        _cursor >= _queue.length || _queue[_cursor].goal.id != current.id;
    if (isLastOfGoal) await _saveGoal(current.id);
    _askNext();
  }

  Future<void> _saveGoal(String goalId) async {
    final answers = _answersByGoal[goalId] ?? const {};
    final numeric = _numericByGoal[goalId] ?? const {};
    final skipped = _skippedByGoal[goalId] ?? const [];
    if (answers.isEmpty && numeric.isEmpty && skipped.isEmpty) return;

    setState(() => _saving = true);
    try {
      await _firestore.saveGoalAnswers(
        widget.uid,
        goalId,
        _date,
        answers,
        numericAnswers: numeric,
        skippedKeys: skipped,
      );
    } catch (e) {
      if (!mounted) return;
      _showError('報告を保存できなかった: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _finish() {
    _post(_role.text('goal_checkin_done', '報告は受け取った。記録しておく。'));
    setState(() => _phase = _Phase.done);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    // タイプ中の吹き出しは1件だけ。流し終えるまでは回答させない
    // （読み終える前に選択肢が出ると急かされて見えるため。DiaryPage と同じ制御）
    int? typingIndex;
    for (var i = _animatedUpTo; i < _lines.length; i++) {
      if (_lines[i].role == 'ai') {
        typingIndex = i;
        break;
      }
    }
    final last = _lines.isEmpty ? null : _lines.last;
    final ready = !_saving && typingIndex == null && last?.role == 'ai';
    final choices = last?.choices;
    final asking = _phase == _Phase.asking;
    final showChoices = ready && choices != null;
    final showInput = ready && choices == null && asking;
    final showSkip = ready && asking;

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
              '本日の報告',
              style: DetectiveTextStyles.appBarTitle(color: c.appBarFg),
            ),
            const SizedBox(height: 2),
            Text(
              '― 追跡中の事件 ―',
              style: DetectiveTextStyles.appBarSubtitle(
                color: c.appBarSubtitle,
              ),
            ),
          ],
        ),
      ),
      body: _initializing
          ? Center(child: CircularProgressIndicator(color: c.gold))
          : Column(
              children: [
                if (_queue.isNotEmpty) _buildProgress(c),
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _lines.length,
                    itemBuilder: (context, index) {
                      final line = _lines[index];
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

                if (_saving)
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: CircularProgressIndicator(color: c.gold),
                  ),

                if (showChoices)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: ChoiceButtons(choices: choices, onSelect: _answer),
                  ),

                if (showSkip)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _skip,
                        icon: Icon(Icons.skip_next, size: 16, color: c.gold),
                        label: Text(
                          'この質問を飛ばす',
                          style: TextStyle(fontSize: 12, color: c.gold),
                        ),
                      ),
                    ),
                  ),

                if (showInput)
                  InputArea(
                    controller: _textController,
                    onSubmit: _answer,
                    hintText: '数字で入力...',
                  ),

                if (_phase == _Phase.done) _buildExit(c),
              ],
            ),
    );
  }

  // 答えた数／全体。DiaryPage の進捗バーと同じ見せ方。
  Widget _buildProgress(AppColors c) {
    final answered = _cursor.clamp(0, _queue.length);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '報告 $answered / ${_queue.length}',
            style: TextStyle(fontSize: 11, color: c.textSecondary),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: _queue.isEmpty ? 0 : answered / _queue.length,
              minHeight: 4,
              backgroundColor: c.cardBorder,
              valueColor: AlwaysStoppedAnimation<Color>(c.gold),
            ),
          ),
        ],
      ),
    );
  }

  // 終わったあとの行き先。日記へ続けるか、今日はここで切り上げるか。
  // pop の戻り値で呼び出し側（MainShell）が日記を開くかを決める。
  Widget _buildExit(AppColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              style: OutlinedButton.styleFrom(
                foregroundColor: c.textSecondary,
                side: BorderSide(color: c.cardBorder),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('今日はここまで'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: c.gold,
                foregroundColor: c.onAccent,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('捜査へ進む'),
            ),
          ),
        ],
      ),
    );
  }
}

// 画面に出す1発言。
//
// owner は「この発言をどの事件のログへ残すか」。null は前置き・締めで、
// 聞く対象の全事件へ複製する（_post の説明を参照）。
class _Line {
  final String role; // 'ai' または 'user'
  final String text;
  final Goal? owner;
  final List<String>? choices; // 非 null なら入力欄の代わりにボタンを出す

  const _Line({
    required this.role,
    required this.text,
    this.owner,
    this.choices,
  });
}
