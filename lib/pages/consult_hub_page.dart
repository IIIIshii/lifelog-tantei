import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/goal_progress.dart';
import '../core/streak.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/detective_text_styles.dart';
import '../models/goal.dart';
import '../roles/roles.dart';
import '../services/firestore_service.dart';
import '../widgets/goal_case_tile.dart';
import '../widgets/section_label.dart';
import 'consult_page.dart';

// ──────────────────────────────────────────────────────────────
// 相談室タブ。追跡中の事件の一覧と、新しい事件を立てる入口。
//
// タブの中身を ConsultPage（チャット）そのものにしていないのは2つの理由から。
// ひとつは、目標が複数になると「どの事件の話か」を先に決める必要があること。
// もうひとつは、IndexedStack がページを破棄しないため、チャットをタブに直接
// 置くと前回の会話が残り続けること。一覧を挟んで push すれば会話は毎回
// 最初から始まり、ConsultPage の戻る矢印もそのまま機能する。
//
// 追跡をやめる操作（解決した / 断念した）をここに置いているのは、ConsultPage が
// 「話す → 見立てが出る → 契約する」の一本道で、そこに分岐を足したくないため。
// ──────────────────────────────────────────────────────────────
class ConsultHubPage extends StatefulWidget {
  final String uid;

  /// MainShell が値を進めるたびに再読込するシグナル。
  /// タブは IndexedStack で保持され破棄されないため、他タブでの変更
  /// （尋問で目標の項目に答えた、など）を反映するにはこの明示的な合図が要る。
  final ValueListenable<int> refreshSignal;

  const ConsultHubPage({
    super.key,
    required this.uid,
    required this.refreshSignal,
  });

  @override
  State<ConsultHubPage> createState() => _ConsultHubPageState();
}

class _ConsultHubPageState extends State<ConsultHubPage> {
  final FirestoreService _firestore = FirestoreService();

  bool _loading = true;
  bool _failed = false;
  Role _role = roleFor(null);
  List<Goal> _goals = const [];
  List<ArchivedGoal> _archived = const [];
  Set<String> _recordedGoalIds = const {};

  @override
  void initState() {
    super.initState();
    widget.refreshSignal.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.refreshSignal.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final goalsFuture = _firestore.getGoals(widget.uid);
    final archivedFuture = _firestore.getArchivedGoals(widget.uid);
    final settingsFuture = _firestore.getUserSettings(widget.uid);
    // 「本日記録済み」の判定に使うのは今日のエントリだけ。専用のメソッドを
    // 足さずに済むよう、getRecentEntries に1日ぶんを頼む。
    final entriesFuture = _firestore.getRecentEntries(widget.uid, 1);

    try {
      final goals = await goalsFuture;
      final archived = await archivedFuture;
      final settings = await settingsFuture;
      final entries = await entriesFuture;
      if (!mounted) return;

      final todayKey = dateKey(DateTime.now());
      Map<String, dynamic>? todayEntry;
      for (final entry in entries) {
        if (entry.key == todayKey) {
          todayEntry = entry.value;
          break;
        }
      }

      setState(() {
        _goals = goals;
        _archived = archived;
        _role = roleFor(settings.selectedRole);
        _recordedGoalIds = goalsRecordedIn(todayEntry, goals);
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      // 失敗しても RefreshIndicator で引き直せるので、画面は保ったまま印だけ出す
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  // 相談室（チャット）を開く。target が null なら新しい事件を立てる。
  // 戻ってきたら無条件に読み直す。契約したのか引き返したのかを戻り値で
  // 受け取らないのは、どちらでも一覧を出し直せば済むため。
  void _openConsult({Goal? target}) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ConsultPage(uid: widget.uid, target: target),
      ),
    ).then((_) => _load());
  }

  // カードのメニュー。見直す・解決した・断念した の3つ。
  void _showGoalMenu(Goal goal) {
    final c = context.colors;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.cardBg,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  goal.title,
                  style: DetectiveTextStyles.cardTitle(color: c.textPrimary),
                ),
              ),
            ),
            Divider(height: 1, color: c.cardBorder),
            ListTile(
              leading: Icon(Icons.edit_note, color: c.gold),
              title: Text(
                '見立てを見直す',
                style: TextStyle(fontSize: 15, color: c.textPrimary),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _openConsult(target: goal);
              },
            ),
            Divider(height: 1, color: c.cardBorder),
            ListTile(
              leading: Icon(Icons.verified_outlined, color: c.gold),
              title: Text(
                '解決した',
                style: TextStyle(fontSize: 15, color: c.textPrimary),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _closeGoal(goal, GoalOutcome.solved);
              },
            ),
            Divider(height: 1, color: c.cardBorder),
            ListTile(
              // 断念を赤字にしない。AppColors にエラー系の色が無く、
              // 足すと全テーマ×全ペアのコントラスト検証に判断が増える。
              // 色を分けなくても、解決と並べば区別は付く。
              leading: Icon(Icons.inventory_2_outlined, color: c.textSecondary),
              title: Text(
                '断念した',
                style: TextStyle(fontSize: 15, color: c.textPrimary),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _closeGoal(goal, GoalOutcome.abandoned);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // 追跡を終える。退避したものは「解決済みの事件」へ移る。
  //
  // 断念の文面を責める調子にしないのは、ホームがストリークの途切れを
  // 咎めないのと同じ方針。やめる判断そのものは依頼人のもの。
  Future<void> _closeGoal(Goal goal, GoalOutcome outcome) async {
    final solved = outcome == GoalOutcome.solved;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(solved ? '事件を解決済みにするか？' : 'この事件の追跡をやめるか？'),
        content: Text(
          solved
              ? '「${goal.title}」を解決済みとして記録する。'
                    '毎日の記録からこの事件の項目が外れる。'
              : '「${goal.title}」を解決済みの事件へ移す。これまでの記録は消えない。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(solved ? '解決にする' : '追跡をやめる'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await _firestore.closeGoal(widget.uid, goal, outcome);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('事件を閉じられなかった: $e')));
      return;
    }
    if (!mounted) return;
    await _load();
  }

  // カードの見出しに出す一言。着手からの日数と期限。
  String _footnoteFor(Goal goal) {
    final deadline = goal.deadline.isEmpty ? '' : ' / 期限 ${goal.deadline}';
    if (goal.createdAt.isEmpty) {
      // 着手日を持たない古いデータでは経過を出さない（分析室と同じ扱い）
      return deadline.isEmpty ? '着手日は記録されていない' : '期限 ${goal.deadline}';
    }
    return '着手から${daysSince(goal.createdAt, DateTime.now())}日$deadline';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isFull = _goals.length >= kMaxTrackedGoals;

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
              '― 追う事件を決める ―',
              style: DetectiveTextStyles.appBarSubtitle(
                color: c.appBarSubtitle,
              ),
            ),
          ],
        ),
      ),

      // ── Body ────────────────────────────────────────────────
      body: RefreshIndicator(
        onRefresh: _load,
        color: c.gold,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            const SectionLabel('追跡中の事件', icon: Icons.flag_outlined),
            const SizedBox(height: 12),

            if (_failed) ...[
              Text(
                '照会に失敗した。引き下げてもう一度試してくれ。',
                style: TextStyle(fontSize: 12, color: c.textSecondary),
              ),
              const SizedBox(height: 12),
            ],

            if (_loading)
              _NoticeCard(message: '照会中…')
            else if (_goals.isEmpty)
              _NoticeCard(
                message: _role.text('goal_empty', '追うべき事件は、まだ決まっていない。'),
              )
            else
              for (final goal in _goals) ...[
                GoalCaseTile(
                  goal: goal,
                  recordedToday: _recordedGoalIds.contains(goal.id),
                  footnote: _footnoteFor(goal),
                  onTap: () => _openConsult(target: goal),
                  onMenu: () => _showGoalMenu(goal),
                ),
                const SizedBox(height: 10),
              ],

            const SizedBox(height: 6),
            _NewCaseTile(
              // 枠が埋まっていても消さずに残し、なぜ押せないのかを出す。
              // 消してしまうと「機能が無い」のか「今は立てられない」のかが
              // 区別できない（設定の前提未設定トグルと同じ考え方）。
              subtitle: isFull
                  ? '追える事件は$kMaxTrackedGoals件まで。どれかを解決するか断念すると新しく立てられる'
                  : '探偵と話して、追う事件を決める',
              onTap: isFull || _loading ? null : () => _openConsult(),
            ),

            // 解決済みが1件も無いうちは見出しごと出さない
            if (_archived.isNotEmpty) ...[
              const SizedBox(height: 32),
              const SectionLabel('解決済みの事件', icon: Icons.inventory_2_outlined),
              const SizedBox(height: 12),
              for (final archived in _archived) ...[
                _ArchivedGoalTile(archived: archived),
                const SizedBox(height: 10),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

// 読み込み中・未設定のときに出す一言。追跡中の事件が並ぶ位置に置いて、
// リストが空でも画面が抜け落ちて見えないようにする。
class _NoticeCard extends StatelessWidget {
  final String message;

  const _NoticeCard({required this.message});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.cardBorder),
      ),
      child: Text(
        message,
        style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.5),
      ),
    );
  }
}

// 「＋ 新しい事件を立てる」。onTap が null なら沈めて押せなくする。
class _NewCaseTile extends StatelessWidget {
  final String subtitle;
  final VoidCallback? onTap;

  const _NewCaseTile({required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onTap != null;
    final foreground = enabled ? c.gold : c.textSecondary;

    return Material(
      color: c.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(4)),
        side: BorderSide(color: c.cardBorder),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.add, size: 18, color: foreground),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '新しい事件を立てる',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: foreground,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: c.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 解決・断念した事件の行。
//
// タップ先を持たせていないのは、閉じた事件にできることが今は無いため。
// 記録そのものは事件簿と分析室に残っており、ここは「何を追い終えたか」の棚。
class _ArchivedGoalTile extends StatelessWidget {
  final ArchivedGoal archived;

  const _ArchivedGoalTile({required this.archived});

  // 退避した日。記録が無ければ着手日を出し、それも無ければ何も出さない。
  String _dateLabel() {
    final at = archived.archivedAt;
    if (at != null) {
      final month = at.month.toString().padLeft(2, '0');
      return '${at.year}-$month';
    }
    return archived.goal.createdAt;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final outcome = archived.outcome;
    final date = _dateLabel();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.cardBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              archived.goal.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: c.textSecondary,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // 結果が読めないものはバッジを出さない。追跡中が1件だけだった頃に
          // 押し出されただけのものが混ざっており、解決とも断念とも言えないため。
          if (outcome != null) ...[
            Text(
              outcome == GoalOutcome.solved ? '解決' : '断念',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: outcome == GoalOutcome.solved ? c.gold : c.textSecondary,
              ),
            ),
            const SizedBox(width: 10),
          ],
          if (date.isNotEmpty)
            Text(date, style: TextStyle(fontSize: 11, color: c.textSecondary)),
        ],
      ),
    );
  }
}
