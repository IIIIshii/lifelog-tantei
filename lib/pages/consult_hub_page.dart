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
import 'goal_log_page.dart';

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
  List<Goal> _closed = const [];
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
    // 追跡中と追跡を終えたものを1回の読み取りで受け取る。
    // 旧 goal-archive に残っているものの引き上げもこの中で済む。
    final goalsFuture = _firestore.getAllGoals(widget.uid);
    final settingsFuture = _firestore.getUserSettings(widget.uid);

    try {
      final divided = await goalsFuture;
      final settings = await settingsFuture;
      // 「本日記録済み」は目標ごとのエントリで判定する
      // （日々の記録が日記のエントリから目標の配下へ移ったため）
      final todayEntries = await _firestore.getGoalEntriesOn(
        widget.uid,
        divided.active.map((goal) => goal.id),
        dateKey(DateTime.now()),
      );
      if (!mounted) return;

      setState(() {
        _goals = divided.active;
        _closed = divided.closed;
        _role = roleFor(settings.selectedRole);
        _recordedGoalIds = goalsRecordedIn(todayEntries, divided.active);
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

  // 追跡中の事件1件の記録を開く。カードのタップ先。
  void _openGoalLog(Goal goal) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => GoalLogPage(uid: widget.uid, goal: goal),
      ),
    );
  }

  // 追跡を終える。閉じたものは「解決済みの事件」へ移る。
  //
  // 断念の文面を責める調子にしないのは、ホームがストリークの途切れを
  // 咎めないのと同じ方針。やめる判断そのものは依頼人のもの。
  Future<void> _closeGoal(Goal goal, GoalStatus status) async {
    final solved = status == GoalStatus.solved;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(solved ? '事件を解決済みにするか？' : 'この事件の追跡をやめるか？'),
        content: Text(
          solved
              ? '「${goal.title}」を解決済みとして記録する。'
                    '毎日の報告からこの事件の質問が外れる。これまでの記録は残る。'
              : '「${goal.title}」を解決済みの事件へ移す。'
                    '毎日の報告から質問が外れるだけで、これまでの記録は残る。',
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
      await _firestore.closeGoal(
        widget.uid,
        goal,
        status,
        closedAt: dateKey(DateTime.now()),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('事件を閉じられなかった: $e')));
      return;
    }
    if (!mounted) return;
    await _load();
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
                  footnote: elapsedLabel(goal, DateTime.now()),
                  // カードのタップ先はその事件の記録。
                  // 事件に対する操作はカードの下のボタンに分けて出す
                  // （タップ先が1つなら右端はシェブロンのままでよい）。
                  onTap: () => _openGoalLog(goal),
                ),
                _GoalActions(
                  onRevise: () => _openConsult(target: goal),
                  onSolved: () => _closeGoal(goal, GoalStatus.solved),
                  onAbandoned: () => _closeGoal(goal, GoalStatus.abandoned),
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
            if (_closed.isNotEmpty) ...[
              const SizedBox(height: 32),
              const SectionLabel('解決済みの事件', icon: Icons.inventory_2_outlined),
              const SizedBox(height: 12),
              for (final goal in _closed) ...[
                // 追跡を終えても記録は目標の配下に残るので、ここからも辿れる
                _ClosedGoalTile(goal: goal, onTap: () => _openGoalLog(goal)),
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

// 事件カードの下に並べる操作。見立てを見直す・解決した・断念した の3つ。
//
// bottom sheet のメニューをやめてボタンにしたのは、何ができるのかが
// 一覧を見た時点で分かるようにするため（長押しやメニューは画面に手がかりが残らない）。
//
// 断念を赤字にしない。AppColors にエラー系の色が無く、足すと全テーマ×全ペアの
// コントラスト検証に判断が増える。色を分けなくても、解決と並べば区別は付く。
class _GoalActions extends StatelessWidget {
  final VoidCallback onRevise;
  final VoidCallback onSolved;
  final VoidCallback onAbandoned;

  const _GoalActions({
    required this.onRevise,
    required this.onSolved,
    required this.onAbandoned,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Wrap(
        spacing: 4,
        children: [
          _ActionButton(
            icon: Icons.edit_note,
            label: '見立てを見直す',
            color: c.gold,
            onTap: onRevise,
          ),
          _ActionButton(
            icon: Icons.verified_outlined,
            label: '解決した',
            color: c.gold,
            onTap: onSolved,
          ),
          _ActionButton(
            icon: Icons.inventory_2_outlined,
            label: '断念した',
            color: c.textSecondary,
            onTap: onAbandoned,
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 15, color: color),
      label: Text(label, style: TextStyle(fontSize: 12, color: color)),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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

// 追跡を終えた事件の行。
//
// ここは「何を追い終えたか」の棚。記録そのものは目標の配下に残っているので、
// タップ先（記録一覧）は追跡を終えたあとも開ける。
class _ClosedGoalTile extends StatelessWidget {
  final Goal goal;
  final VoidCallback onTap;

  const _ClosedGoalTile({required this.goal, required this.onTap});

  // 追跡を終えた月。記録が無ければ着手日を出し、それも無ければ何も出さない。
  String _dateLabel() {
    // 'YYYY-MM-DD' の頭7文字が 'YYYY-MM'
    if (goal.closedAt.length >= 7) return goal.closedAt.substring(0, 7);
    return goal.createdAt;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final date = _dateLabel();
    // 理由が記録されていないものはバッジを出さない。追跡中が1件だけだった頃に
    // 押し出されただけのものが混ざっており、解決とも断念とも言えないため。
    final label = switch (goal.status) {
      GoalStatus.solved => '解決',
      GoalStatus.abandoned => '断念',
      _ => '',
    };

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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  goal.title,
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
              if (label.isNotEmpty) ...[
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: goal.status == GoalStatus.solved
                        ? c.gold
                        : c.textSecondary,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              if (date.isNotEmpty)
                Text(
                  date,
                  style: TextStyle(fontSize: 11, color: c.textSecondary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
