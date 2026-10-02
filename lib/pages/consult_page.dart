import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:uuid/uuid.dart';

import '../core/streak.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/detective_text_styles.dart';
import '../models/goal.dart';
import '../models/user_settings.dart';
import '../roles/roles.dart';
import '../services/firestore_service.dart';
import '../services/gemini_service.dart';
import '../widgets/choice_buttons.dart';
import '../widgets/input_area.dart';
import '../widgets/message_bubble.dart';

// 相談室。探偵と壁打ちして、ふんわりした願いを追いかけられる目標に落とす画面。
// 相談室タブ（ConsultHubPage）の事件一覧から push で開く。
// target を渡せばその事件の見直し、null なら新しい事件を立てる。
//
// タブに直接置かず一覧から push するのは、IndexedStack がページを破棄しないため。
// タブ直置きにすると前回の会話が残り続け、「どの事件の話か」も選べない。
//
// DiaryPage のような12状態のステートマシンにしていないのは、ここが
// 「話す → 見立てが出る → 契約する」の一本道で、質問キューも分岐モードも無いため。
// 「解決した / 断念した」をここに置いていないのも同じ理由で、一本道に分岐を足さない
// （追跡をやめる操作は事件一覧の仕事）。
//
// 壁打ちの会話は保存しない。この画面の成果物は目標そのもの
// （users/{uid}/goals/{goalId}）で、見立てが決まったあとに経緯を読み返す先が無いため。
//
// 毎日の報告（GoalCheckInPage）は逆で、会話を
// goals/{goalId}/entries/{date}/conversation に残す。記録一覧から
// 「その日、何を聞かれて何と答えたか」を読み返すからで、保存する／しないの違いは
// 読み返す先があるかどうかで決めている。
enum _Stage {
  talking, // 壁打ち中
  reviewing, // AIが見立てを出した。採用するか確認している
  saved, // 契約成立。独自質問の承認だけが残る
}

class ConsultPage extends StatefulWidget {
  final String uid;

  /// 見直す対象の目標。null なら新しく立てる。
  final Goal? target;

  const ConsultPage({super.key, required this.uid, this.target});

  @override
  State<ConsultPage> createState() => _ConsultPageState();
}

class _ConsultPageState extends State<ConsultPage> {
  final FirestoreService _firestore = FirestoreService();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();

  late final String _apiKey;
  late GeminiService _gemini;
  Role _currentRole = roleFor(null);

  // 画面に表示する会話。Gemini にもこの形のまま渡す（GeminiService._buildHistory の流儀）
  final List<Map<String, String>> _messages = [];

  _Stage _stage = _Stage.talking;
  bool _initializing = true;
  bool _isLoading = false;

  // 見直す対象。新しく立てるときは null のまま。
  // widget.target をそのまま使わず _init() で読み直すのは、一覧が古くても
  // 最新の中身で話を始められるようにするため。
  Goal? _target;

  // 今追っている目標すべて。行動項目の残り枠の計算に使う。
  List<Goal> _allGoals = const [];

  // この相談で採用できる行動項目の件数
  // （全目標合計の残り枠と、1目標あたりの上限の小さい方）
  int _slots = kMaxGoalActions;

  Goal? _draft; // AIが提案した見立て。契約後は保存済みの目標が入る
  final Set<String> _selectedActionIds = {}; // 採用する行動項目
  final Set<String> _acceptedQuestions = {}; // 独自質問リストへ追加済みの質問

  List<String>? _currentChoices; // null ならテキスト入力を表示する
  int _animatedUpTo = 0; // タイプライター表示を流し終えた位置

  // 依頼人が何か話したか。「ここまでで見立てを立てる」を出すかの判定に使う
  bool get _hasUserSpoken => _messages.any((m) => m['role'] == 'user');

  @override
  void initState() {
    super.initState();
    _apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    _init();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _textController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  // 設定・自己分析・目標を並行で読み、この相談で使う Gemini クライアントを組み立てる。
  // 自己分析は共有トグルの判定ごと GeminiService に委ねる（DiaryPage._initGemini と同じ）。
  Future<void> _init() async {
    try {
      final settingsFuture = _firestore.getUserSettings(widget.uid);
      final selfAnalysisFuture = _firestore.getSelfAnalysis(widget.uid);
      final goalsFuture = _firestore.getGoals(widget.uid);
      final settings = await settingsFuture;
      final selfAnalysis = await selfAnalysisFuture;
      final goals = await goalsFuture;
      if (!mounted) return;

      // 一覧から渡された目標は、読み直した方で置き換える。
      // 一覧の表示が古いまま見直しに入っても、最新の中身を土台に話せるようにするため。
      final requested = widget.target;
      final target = requested == null
          ? null
          : goals.firstWhere(
              (goal) => goal.id == requested.id,
              orElse: () => requested,
            );

      _currentRole = roleFor(settings.selectedRole);
      _gemini = GeminiService(
        _apiKey,
        settings.selectedRole,
        selfAnalysis: selfAnalysis,
      );
      setState(() {
        _allGoals = goals;
        _target = target;
        _slots = selectableActionSlots(goals, excludingGoalId: target?.id);
        _initializing = false;
      });

      // どの事件の話かは一覧で決まっているので、ここで選ばせる必要はない。
      _postAiMessage(
        target == null
            ? _currentRole.text(
                'intro_consult',
                '追いたい事件があるらしいな。漠然としたままでいい、話してみろ。',
              )
            : _currentRole.text('consult_revise', 'どこを変えたい？ 話してくれ。'),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _initializing = false);
      _showError('相談室を開けなかった: $e');
    }
  }

  // 探偵の発言を会話に足す。選択肢を渡すとテキスト入力の代わりにボタンを出す。
  void _postAiMessage(String text, {List<String>? choices}) {
    setState(() {
      _messages.add({'role': 'ai', 'text': text});
      _currentChoices = choices;
    });
    _scrollToBottom();
  }

  void _postUserMessage(String text) {
    setState(() {
      _messages.add({'role': 'user', 'text': text});
      _currentChoices = null;
    });
    _scrollToBottom();
  }

  // 依頼人の発言を受けて次の一手を決める。
  // 選択肢ボタンからもテキスト入力からもここに来る。
  Future<void> _sendUserReply(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _textController.clear();

    if (_stage == _Stage.reviewing) {
      _postUserMessage(trimmed);
      if (trimmed == 'この方針で行く') {
        await _saveGoal();
      } else {
        // 見立ては捨てずに残す。話し直した結果が出れば上書きされる
        setState(() => _stage = _Stage.talking);
        _postAiMessage(_currentRole.text('consult_rethink', 'どこが違う？ 聞かせてくれ。'));
      }
      return;
    }

    _postUserMessage(trimmed);
    await _consult();
  }

  // Gemini に相談の続きを投げる。
  // forcePropose のときは材料が足りなくても見立てを出させる。
  Future<void> _consult({bool forcePropose = false}) async {
    setState(() => _isLoading = true);
    try {
      final target = _target;
      final result = await _gemini.consultGoal(
        _messages,
        today: dateKey(DateTime.now()),
        // 見直しのときだけ、今の目標を土台として渡す
        target: target,
        // 同じ狙いの事件を重ねて立てさせないよう、他に追っているものも伝える
        otherGoals: _allGoals
            .where((goal) => goal.id != target?.id)
            .toList(growable: false),
        actionBudget: _slots,
        forcePropose: forcePropose,
      );
      if (!mounted) return;

      final goal = result.goal;
      if (result.ready && goal != null) {
        _titleController.text = goal.title;
        // 既定は枠に収まるぶんだけ採用する。
        // AI は優先度の高い順に並べるので先頭から採る。
        _selectedActionIds
          ..clear()
          ..addAll(goal.actions.take(_slots).map((a) => a.id));
        setState(() {
          _draft = goal;
          _stage = _Stage.reviewing;
        });
        _postAiMessage(result.reply, choices: const ['この方針で行く', 'もう少し話す']);
        return;
      }
      _postAiMessage(result.reply);
    } catch (e) {
      if (!mounted) return;
      _showError('AIエラー: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _scrollToBottom();
      }
    }
  }

  // 見立てを目標として確定する。
  // 見直しなら同じ id で上書きし、新規なら1件増える。
  // 古い目標を自動で退避することはしない ―― 追跡をやめるかどうかは
  // 事件一覧で明示的に決める（解決した / 断念した）。
  Future<void> _saveGoal() async {
    final draft = _draft;
    if (draft == null) return;

    final target = _target;
    final editedTitle = _titleController.text.trim();

    // 採用した項目を絞ってから id を引き継ぐ。_selectedActionIds は見立てが
    // 発行したばかりの id を持つので、引き継ぎを先にすると照合できなくなる。
    final selected = draft.copyWith(
      actions: draft.actions
          .where((a) => _selectedActionIds.contains(a.id))
          .toList(growable: false),
    );
    final goal = carryOverActionIds(selected, target).copyWith(
      // copyWith は null なら現状維持なので、新規（target が null）では
      // 見立てが持つ uuid と今日の日付がそのまま残る。
      // id を変えると保存済みの 'goal_<actionId>' の回答と対応が切れ、
      // createdAt を今日にすると分析室の「着手から n 日」が巻き戻る。
      id: target?.id,
      createdAt: target?.createdAt,
      title: editedTitle.isEmpty ? draft.title : editedTitle,
    );

    setState(() => _isLoading = true);
    try {
      await _firestore.saveGoal(widget.uid, goal);
      if (!mounted) return;
      setState(() {
        _target = goal;
        _draft = goal;
        _stage = _Stage.saved;
      });
      _postAiMessage(_currentRole.text('consult_saved', '契約成立だ。今日から追跡を始める。'));
    } catch (e) {
      if (!mounted) return;
      _showError('目標を保存できなかった: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 提案された独自質問を、設定の独自質問リストへ追加する。
  //
  // 設定は毎回読み直してから書く。saveUserSettings は .set() の全置換なので、
  // 相談室に入る前に読んだ設定を握ったまま書くと、その間に設定画面で変えた
  // トグルや質問を巻き戻してしまう。
  Future<void> _acceptQuestion(String text) async {
    if (_acceptedQuestions.contains(text)) return;
    setState(() => _acceptedQuestions.add(text));
    try {
      final settings = await _firestore.getUserSettings(widget.uid);
      if (settings.customQuestions.any((q) => q.text == text)) return;
      await _firestore.saveUserSettings(
        widget.uid,
        settings.copyWith(
          customQuestions: [
            ...settings.customQuestions,
            CustomQuestion(
              id: const Uuid().v4(),
              text: text,
              source: CustomQuestionSource.consult,
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _acceptedQuestions.remove(text));
      _showError('質問を追加できなかった: $e');
    }
  }

  // 行動項目の採用／不採用を切り替える。
  // 外す操作はいつでも通し、増やす操作だけ残り枠で止める
  // （枠がいっぱいのときに「外して付け替える」ができなくなるのを避ける）。
  void _toggleAction(String id) {
    if (_selectedActionIds.remove(id)) {
      setState(() {});
      return;
    }
    if (_selectedActionIds.length >= _slots) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('毎日の記録に加えられる項目は$_slots件までだ')));
      return;
    }
    setState(() => _selectedActionIds.add(id));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void _showError(String message) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('エラー'),
        content: SelectableText(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    // タイプ中の吹き出しは1件だけ。流し終えるまでは回答させない
    // （DiaryPage と同じ表示制御。読み終える前に選択肢が出ると急かされて見える）
    int? typingIndex;
    for (var i = _animatedUpTo; i < _messages.length; i++) {
      if (_messages[i]['role'] == 'ai') {
        typingIndex = i;
        break;
      }
    }
    final isTyping = typingIndex != null;
    final lastIsAi = _messages.isNotEmpty && _messages.last['role'] == 'ai';
    final ready = !_isLoading && !isTyping && lastIsAi;
    final showChoices = ready && _currentChoices != null;
    final showInput =
        ready && _currentChoices == null && _stage != _Stage.saved;
    // 壁打ちが長引いたときに自分から打ち切れる逃げ道
    final showPropose = showInput && _hasUserSpoken;

    return Scaffold(
      backgroundColor: c.background,

      // ── AppBar ──────────────────────────────────────────────
      appBar: AppBar(
        backgroundColor: c.appBarBg,
        foregroundColor: c.appBarFg,
        elevation: 0,
        toolbarHeight: 64,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '相談室',
              style: DetectiveTextStyles.appBarTitle(color: c.appBarFg),
            ),
            const SizedBox(height: 2),
            Text(
              // 新しく立てるのか、今ある事件を見直すのかを見出しで示す
              _target == null ? '― 事件の見立てを立てる ―' : '― 事件を見直す ―',
              style: DetectiveTextStyles.appBarSubtitle(
                color: c.appBarSubtitle,
              ),
            ),
          ],
        ),
      ),

      // ── Body ────────────────────────────────────────────────
      body: _initializing
          ? Center(child: CircularProgressIndicator(color: c.gold))
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    // 見立てが出たら会話の末尾にカードを1枚差し込む
                    itemCount: _messages.length + (_draft != null ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _messages.length) {
                        return _buildDraftSection();
                      }
                      final msg = _messages[index];
                      return MessageBubble(
                        role: msg['role']!,
                        text: msg['text']!,
                        animate: index == typingIndex,
                        onAnimationFinished: () {
                          if (!mounted) return;
                          setState(() => _animatedUpTo = index + 1);
                          _scrollToBottom();
                        },
                      );
                    },
                  ),
                ),

                if (_isLoading)
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: CircularProgressIndicator(color: c.gold),
                  ),

                if (showChoices)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: ChoiceButtons(
                      choices: _currentChoices!,
                      onSelect: _sendUserReply,
                    ),
                  ),

                if (showPropose)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => _consult(forcePropose: true),
                        icon: Icon(Icons.gavel, size: 16, color: c.gold),
                        label: Text(
                          'ここまでで見立てを立てる',
                          style: TextStyle(fontSize: 12, color: c.gold),
                        ),
                      ),
                    ),
                  ),

                if (showInput)
                  InputArea(
                    controller: _textController,
                    onSubmit: _sendUserReply,
                    hintText: '相談内容を入力...',
                  ),

                if (_stage == _Stage.saved)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: c.gold,
                          foregroundColor: c.onAccent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('事件一覧へ戻る'),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  // 会話の末尾に出す、見立てカード＋（契約後は）独自質問の提案。
  Widget _buildDraftSection() {
    final draft = _draft!;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GoalDraftCard(
            goal: draft,
            editable: _stage == _Stage.reviewing,
            slots: _slots,
            titleController: _titleController,
            selectedActionIds: _selectedActionIds,
            onToggleAction: _toggleAction,
          ),
          if (_stage == _Stage.saved &&
              draft.suggestedQuestions.isNotEmpty) ...[
            const SizedBox(height: 16),
            _QuestionProposalCard(
              questions: draft.suggestedQuestions,
              accepted: _acceptedQuestions,
              onAccept: _acceptQuestion,
            ),
          ],
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// 見立てカード
//
// 事件報告書（DiaryCard）と同じゴールド枠の書類デザイン。
// 確認中（editable）はタイトルを書き換えられ、行動項目を選び直せる。
// 単位や目標値まで編集できるフォームは作らない ―― 会話で直せるのがこの機能の
// 売りなので、細かい修正は「もう少し話す」で探偵に言い直してもらう。
// ──────────────────────────────────────────────────────────────
class _GoalDraftCard extends StatelessWidget {
  final Goal goal;
  final bool editable;

  /// この事件で採用できる行動項目の件数。毎日の記録の残り枠。
  final int slots;

  final TextEditingController titleController;
  final Set<String> selectedActionIds;
  final ValueChanged<String> onToggleAction;

  const _GoalDraftCard({
    required this.goal,
    required this.editable,
    required this.slots,
    required this.titleController,
    required this.selectedActionIds,
    required this.onToggleAction,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.cardBg,
        border: Border.all(color: c.gold, width: 1.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 見出し ────────────────────────────────────────
          Row(
            children: [
              Icon(Icons.flag_outlined, size: 14, color: c.gold),
              const SizedBox(width: 6),
              Text(
                '捜査方針',
                style: DetectiveTextStyles.caseNumber(color: c.gold),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── 目標そのもの ──────────────────────────────────
          if (editable)
            TextField(
              controller: titleController,
              style: DetectiveTextStyles.cardTitle(color: c.textPrimary),
              maxLines: 2,
              minLines: 1,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: c.background,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: c.cardBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: c.cardBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: c.gold, width: 1.5),
                ),
              ),
            )
          else
            Text(
              goal.title,
              style: DetectiveTextStyles.cardTitle(color: c.textPrimary),
            ),

          // ── 達成の基準・期限 ──────────────────────────────
          if (goal.metric.isNotEmpty) ...[
            const SizedBox(height: 10),
            _Labeled(label: '解決の条件', value: goal.metric),
          ],
          if (goal.deadline.isNotEmpty) ...[
            const SizedBox(height: 6),
            _Labeled(label: '期限', value: goal.deadline),
          ],

          // ── 毎日追う項目 ──────────────────────────────────
          // 枠が埋まっているときは AI も項目を出さない。何も言わずに
          // 項目欄が消えると不具合に見えるので、理由を1行で添える。
          if (editable && slots == 0) ...[
            const SizedBox(height: 14),
            Text(
              '毎日の記録は$kMaxTotalGoalActions件で埋まっている。この事件は方針だけを決める',
              style: TextStyle(fontSize: 11, color: c.textSecondary),
            ),
          ],
          if (goal.actions.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              editable ? '毎日の記録に加える項目（残り枠 $slots 件・外すものはタップ）' : '毎日の記録に加えた項目',
              style: TextStyle(fontSize: 11, color: c.textSecondary),
            ),
            const SizedBox(height: 4),
            for (final action in goal.actions)
              _ActionRow(
                action: action,
                editable: editable,
                selected: selectedActionIds.contains(action.id),
                onTap: () => onToggleAction(action.id),
              ),
          ],
        ],
      ),
    );
  }
}

// 「ラベル 値」の1行
class _Labeled extends StatelessWidget {
  final String label;
  final String value;

  const _Labeled({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label ', style: TextStyle(fontSize: 12, color: c.textSecondary)),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontSize: 13, color: c.textPrimary, height: 1.4),
          ),
        ),
      ],
    );
  }
}

// 行動項目1件。確認中はタップで採用／不採用を切り替えられる。
class _ActionRow extends StatelessWidget {
  final GoalAction action;
  final bool editable;
  final bool selected;
  final VoidCallback onTap;

  const _ActionRow({
    required this.action,
    required this.editable,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // 不採用にした項目は、消さずに沈めて「戻せる」ことを見せる
    final dimmed = editable && !selected;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            editable
                ? (selected ? Icons.check_box : Icons.check_box_outline_blank)
                : (action.isNumeric ? Icons.straighten : Icons.check_circle),
            size: 18,
            color: dimmed ? c.textSecondary : c.gold,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              action.label,
              style: TextStyle(
                fontSize: 14,
                color: dimmed ? c.textSecondary : c.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            action.isNumeric
                ? (action.unit.isEmpty ? '数値' : '数値・${action.unit}')
                : '達成／未達',
            style: TextStyle(fontSize: 11, color: c.textSecondary),
          ),
        ],
      ),
    );
    if (!editable) return row;
    return InkWell(onTap: onTap, child: row);
  }
}

// ──────────────────────────────────────────────────────────────
// 独自質問の提案カード
//
// 契約が成立したあとに出す。タップした質問は設定の「独自質問リスト」へ入り、
// 翌日からの捜査で聞かれるようになる。
// 行動項目（毎日の計測）と混同されやすいので、別カードに分けて説明を添える。
// ──────────────────────────────────────────────────────────────
class _QuestionProposalCard extends StatelessWidget {
  final List<String> questions;
  final Set<String> accepted;
  final ValueChanged<String> onAccept;

  const _QuestionProposalCard({
    required this.questions,
    required this.accepted,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '◆ 尋問に加える質問',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: c.gold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '数字では拾えないことを聞く問い。選ぶと独自質問リストに入る',
                  style: TextStyle(fontSize: 11, color: c.textSecondary),
                ),
              ],
            ),
          ),
          for (final question in questions) ...[
            Divider(height: 1, color: c.cardBorder),
            _QuestionRow(
              text: question,
              accepted: accepted.contains(question),
              onTap: () => onAccept(question),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuestionRow extends StatelessWidget {
  final String text;
  final bool accepted;
  final VoidCallback onTap;

  const _QuestionRow({
    required this.text,
    required this.accepted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: accepted ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 13,
                  color: accepted ? c.textSecondary : c.textPrimary,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              accepted ? Icons.check_circle : Icons.add_circle_outline,
              size: 22,
              color: accepted ? c.textSecondary : c.gold,
            ),
          ],
        ),
      ),
    );
  }
}
