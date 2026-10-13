import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/daily_record.dart';
import '../core/goal_progress.dart';
import '../core/streak.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/detective_text_styles.dart';
import '../models/goal.dart';
import '../models/mbti_type.dart';
import '../models/self_analysis.dart';
import '../roles/roles.dart';
import '../services/firestore_service.dart';
import '../widgets/case_archive_tile.dart';
import '../widgets/goal_case_tile.dart';
import '../widgets/section_label.dart';
import '../widgets/status_badge.dart';
import 'diary_detail_page.dart';
import 'diary_page.dart';
import 'record_sheet_page.dart';
import 'role_select_page.dart';
import 'self_analysis_page.dart';

// ストリーク算出とヒートマップに使う遡り日数。
// 7日ぶんのヒートマップには足りるが、連続日数はここが上限になるため余裕を持たせている。
const int _lookbackDays = 30;

// ホーム（事務所）タブに表示する「直近の事件」の最大件数。
// これ以上は事件簿タブの仕事なので、ホームでは3件に留める。
const int _recentPreviewCount = 3;

const List<String> _weekdayJa = ['月', '火', '水', '木', '金', '土', '日'];

/// 今日の捜査の進み具合。ホームが読み込んで MainShell へ渡し、
/// FAB のラベルと「日々の記録を挟むか」の判定に使う。
typedef TodayStatus = ({int filled, int total, bool diaryDone});

// ──────────────────────────────────────────────────────────────
// ホーム画面（事務所タブ）
//
// 「本日の捜査」カードで、今日の2段（日々の記録 → 事件簿）の進み具合を最初に見せる。
// 通しで進める主要動線は MainShell 側の Extended FAB が担い、
// ここでは各段を個別に開けるようにしている（項目だけ書き足したいとき用）。
// ──────────────────────────────────────────────────────────────
class HomePage extends StatefulWidget {
  final String uid;

  /// MainShell が値を進めるたびに再読込するシグナル。
  /// タブは IndexedStack で保持され破棄されないため、他タブでの変更
  /// （探偵の指名、デモデータ投入など）を反映するにはこの明示的な合図が要る。
  final ValueListenable<int> refreshSignal;

  /// 今日の進み具合を MainShell へ伝える出力。読み込み前は null。
  /// FAB のために Firestore をもう一度読まないよう、ここが読んだ結果を渡す。
  final ValueNotifier<TodayStatus?> todayStatus;

  /// 「追跡中の事件」から相談室タブへ移動するためのコールバック。
  /// タブの index は MainShell の関心事なので、ここでは持たない。
  final VoidCallback onOpenConsultTab;

  const HomePage({
    super.key,
    required this.uid,
    required this.refreshSignal,
    required this.todayStatus,
    required this.onOpenConsultTab,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FirestoreService _firestore = FirestoreService();

  bool _loading = true;
  bool _failed = false;
  Role _role = roleFor(null);
  SelfAnalysis _selfAnalysis = SelfAnalysis.defaults();
  List<Goal> _goals = const [];
  Set<String> _recordedGoalIds = const {}; // 今日、項目に記録した目標の id
  Set<String> _written = const {};
  ({int filled, int total}) _progress = (filled: 0, total: 0);
  String? _todayDiary;
  List<MapEntry<String, Map<String, dynamic>>> _recent = const [];

  @override
  void initState() {
    super.initState();
    widget.refreshSignal.addListener(_handleRefreshSignal);
    _load();
  }

  @override
  void dispose() {
    widget.refreshSignal.removeListener(_handleRefreshSignal);
    super.dispose();
  }

  void _handleRefreshSignal() => _load();

  // 本日の捜査カードと直近リストに必要なデータをまとめて取得する。
  Future<void> _load() async {
    final recordsFuture = _firestore.getRecentRecords(
      widget.uid,
      _lookbackDays,
    );
    final diariesFuture = _firestore.getRecentDiaries(
      widget.uid,
      _lookbackDays,
    );
    final fieldsFuture = _firestore.getFields(widget.uid);
    final settingsFuture = _firestore.getUserSettings(widget.uid);
    final selfAnalysisFuture = _firestore.getSelfAnalysis(widget.uid);
    final goalsFuture = _firestore.getGoals(widget.uid);

    try {
      final records = await recordsFuture;
      final diaries = await diariesFuture;
      final fields = await fieldsFuture;
      final settings = await settingsFuture;
      final selfAnalysis = await selfAnalysisFuture;
      final goals = await goalsFuture;
      if (!mounted) return;

      final now = DateTime.now();
      final todayKey = dateKey(now);
      Map<String, dynamic>? todayRecord;
      for (final e in records) {
        if (e.key == todayKey) todayRecord = e.value;
      }
      final progress = recordProgress(
        fieldsForDay(fields, goals, now),
        todayRecord,
      );

      // 本文のある日記だけを新しい順に
      final withText =
          diaries
              .where(
                (e) => ((e.value['text'] as String?) ?? '').trim().isNotEmpty,
              )
              .toList()
            ..sort((a, b) => b.key.compareTo(a.key));
      String? todayDiary;
      for (final e in withText) {
        if (e.key == todayKey) todayDiary = e.value['text'] as String;
      }

      setState(() {
        _written = recordedDates(records, diaries);
        _recent = withText.where((e) => e.key != todayKey).toList();
        _todayDiary = todayDiary;
        _progress = progress;
        _role = roleFor(settings.selectedRole);
        _selfAnalysis = selfAnalysis;
        _goals = goals;
        _recordedGoalIds = goalsRecordedIn(todayRecord, goals);
        _loading = false;
        _failed = false;
      });
      widget.todayStatus.value = (
        filled: progress.filled,
        total: progress.total,
        diaryDone: todayDiary != null,
      );
    } catch (_) {
      if (!mounted) return;
      // 失敗しても RefreshIndicator で引き直せるので、画面は保ったまま印だけ出す
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  // 「日々の記録」の段：今日の表を開く
  void _openRecord() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => RecordSheetPage(uid: widget.uid),
      ),
    ).then((_) => _load());
  }

  // 「事件簿」の段：まとめ済みなら報告書、まだなら聴取を開く
  void _openDiary() {
    final diary = _todayDiary;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => diary == null
            ? const DiaryPage()
            : DiaryDetailPage(
                date: dateKey(DateTime.now()),
                diary: diary,
                uid: widget.uid,
                firestore: _firestore,
              ),
      ),
    ).then((_) => _load());
  }

  // 担当探偵の行のタップ：ロール選択ページへ。
  // 探偵はボトムナビのタブではなくなったので、設定タブへ飛ばして一覧から
  // 探させるのではなく、ここから直接 push する（タップ先を変えない）。
  void _openRoleSelect() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const RoleSelectPage()),
    ).then((_) => _load());
  }

  // 捜査資料カードのタップ：自己分析ページへ。
  // ホームから push するので、戻ってきたら _load() でカードの表示を取り直す
  // （MainShell の _homeRefresh はタブ切り替え用なのでここでは使わない）。
  void _openSelfAnalysis() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => SelfAnalysisPage(uid: widget.uid),
      ),
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final today = DateTime.now();
    final preview = _recent.take(_recentPreviewCount).toList();

    return Scaffold(
      backgroundColor: c.background,

      // ── AppBar ──────────────────────────────────────────────
      // タイトルにサブタイトルを重ねることで探偵事務所の看板風に見せる
      appBar: AppBar(
        backgroundColor: c.appBarBg,
        elevation: 0,
        toolbarHeight: 64,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ライフログ探偵',
              style: DetectiveTextStyles.appBarTitle(color: c.appBarFg),
            ),
            const SizedBox(height: 2),
            Text(
              '― 事件、受け付けます ―',
              style: DetectiveTextStyles.appBarSubtitle(
                color: c.appBarSubtitle,
              ),
            ),
          ],
        ),
      ),

      // ── Body ────────────────────────────────────────────────
      // Column ではなく CustomScrollView にすることで、小型端末や
      // 文字サイズ拡大時でも RenderFlex overflow が起きない構造にする。
      body: RefreshIndicator(
        color: c.gold,
        backgroundColor: c.cardBg,
        onRefresh: _load,
        child: CustomScrollView(
          // 中身が画面に収まっているときも引っ張って更新できるようにする
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── 本日の捜査（ヒーロー） ──────────────────────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              sliver: SliverToBoxAdapter(
                child: _TodayCaseCard(
                  loading: _loading,
                  today: today,
                  progress: _progress,
                  todayDiary: _todayDiary,
                  role: _role,
                  weekFlags: recentDayFlags(_written, today, 7),
                  streak: calcStreak(_written, today),
                  onTapRecord: _openRecord,
                  onTapDiary: _openDiary,
                  onTapRole: _openRoleSelect,
                ),
              ),
            ),

            if (_failed)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    '記録を読み込めませんでした。下に引いて再試行してください。',
                    style: TextStyle(fontSize: 12, color: c.textSecondary),
                  ),
                ),
              ),

            // ── 追跡中の事件（目標） ────────────────────────
            // 今日なにをするかに直接効く情報なので、依頼人の属性を扱う
            // 「捜査資料」より前、本日の事件のすぐ下に置く。
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(20, 28, 20, 12),
              sliver: SliverToBoxAdapter(
                child: SectionLabel('追跡中の事件', icon: Icons.flag_outlined),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: _loading || _goals.isEmpty
                  // 読み込み中も未設定も1枚で受ける。未設定でもタップできるように
                  // するのは、「立てる場所がある」こと自体をホームで伝えたいため。
                  ? SliverToBoxAdapter(
                      child: _GoalNoticeTile(
                        message: _loading
                            ? '照会中…'
                            : _role.text('goal_empty', '追うべき事件は、まだ決まっていない。'),
                        onTap: widget.onOpenConsultTab,
                      ),
                    )
                  : SliverList.separated(
                      itemCount: _goals.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final goal = _goals[index];
                        return GoalCaseTile(
                          goal: goal,
                          recordedToday: _recordedGoalIds.contains(goal.id),
                          // どれを押しても行き先は同じ相談室タブ。個別の事件を
                          // 直接開かないのは、切り替えた先でどれを選ぶかを見せた方が
                          // 「他にも追っている事件がある」ことが伝わるため。
                          onTap: widget.onOpenConsultTab,
                        );
                      },
                    ),
            ),

            // ── 捜査資料（依頼人自身の情報） ────────────────
            // 事件そのものではなく「誰の事件簿か」を扱う区画。
            // 自己分析の項目が増えたらここにカードを足していく。
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(20, 28, 20, 12),
              sliver: SliverToBoxAdapter(
                child: SectionLabel('捜査資料', icon: Icons.badge_outlined),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverToBoxAdapter(
                child: _SelfAnalysisTile(
                  loading: _loading,
                  selfAnalysis: _selfAnalysis,
                  onTap: _openSelfAnalysis,
                ),
              ),
            ),

            // ── 直近の事件 ──────────────────────────────────
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(20, 28, 20, 12),
              sliver: SliverToBoxAdapter(child: SectionLabel('直近の事件')),
            ),

            if (!_loading && preview.isEmpty)
              const SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverToBoxAdapter(child: _EmptyRecent()),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, i) {
                    final entry = preview[i];
                    final diary = entry.value['text'] as String;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: CaseArchiveTile(
                        date: entry.key,
                        diary: diary,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => DiaryDetailPage(
                              date: entry.key,
                              diary: diary,
                              uid: widget.uid,
                              firestore: _firestore,
                            ),
                          ),
                        ).then((_) => _load()),
                      ),
                    );
                  }, childCount: preview.length),
                ),
              ),

            // FAB に隠れないための下部余白
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// 本日の捜査カード（ヒーロー領域）
//
// 既存カードのデザイン言語（cardBg + cardBorder 枠 + 左端ゴールド4px縦帯）を
// 踏襲しつつ、今日の2段（日々の記録・事件簿）・担当探偵・週間ヒートマップを
// 1枚にまとめる。各段は行ごとにタップでき、その段だけを開く。
// ──────────────────────────────────────────────────────────────
class _TodayCaseCard extends StatelessWidget {
  final bool loading;
  final DateTime today;
  final ({int filled, int total}) progress;
  final String? todayDiary;
  final Role role;
  final List<bool> weekFlags; // 7件、末尾が今日
  final int streak;
  final VoidCallback onTapRecord;
  final VoidCallback onTapDiary;
  final VoidCallback onTapRole;

  const _TodayCaseCard({
    required this.loading,
    required this.today,
    required this.progress,
    required this.todayDiary,
    required this.role,
    required this.weekFlags,
    required this.streak,
    required this.onTapRecord,
    required this.onTapDiary,
    required this.onTapRole,
  });

  // 記録は「項目が無い」日もあるので、その日は済んだものとして扱う
  bool get _recordDone => progress.filled >= progress.total;

  String get _dateLabel =>
      '${today.year}年${today.month}月${today.day}日'
      '（${_weekdayJa[today.weekday - 1]}）';

  // ストリークが切れていても責める表現にならないよう、
  // 0日のときは直近7日の記録日数という穏当な言い方に切り替える。
  String get _streakLabel {
    if (streak > 0) return '$streak日連続';
    final count = weekFlags.where((e) => e).length;
    return '直近7日で$count日';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final diaryDone = todayDiary != null;
    final done = diaryDone && _recordDone;

    return Material(
      color: c.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(4)),
        side: BorderSide(color: c.cardBorder),
      ),
      child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 左端のゴールドアクセントボーダー
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: c.gold,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    bottomLeft: Radius.circular(4),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                  child: loading
                      ? const _TodayCardPlaceholder()
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── 見出し行 ───────────────────────
                            Row(
                              children: [
                                Icon(
                                  Icons.description,
                                  size: 16,
                                  color: c.gold,
                                ),
                                const SizedBox(width: 6),
                                // Spacer ではなく Expanded にする。
                                // 端末の文字サイズを上げるとラベルとバッジが
                                // 横幅を食い合って overflow するため。
                                Expanded(
                                  child: Text(
                                    '本日の捜査',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: c.gold,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                StatusBadge(done: done),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // ── 日付 ───────────────────────────
                            Text(
                              _dateLabel,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: c.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),

                            // ── 今日の2段 ─────────────────────
                            _StepRow(
                              index: 1,
                              title: '日々の記録',
                              status: progress.total == 0
                                  ? '項目なし'
                                  : '記入 ${progress.filled} / ${progress.total}',
                              done: _recordDone,
                              onTap: onTapRecord,
                            ),
                            _StepRow(
                              index: 2,
                              title: '事件簿',
                              status: diaryDone ? 'まとめ済み' : '未作成',
                              done: diaryDone,
                              preview: diaryDone && todayDiary!.trim().isNotEmpty
                                  ? todayDiary
                                  : null,
                              onTap: onTapDiary,
                            ),

                            const SizedBox(height: 6),
                            Divider(height: 1, color: c.cardBorder),
                            const SizedBox(height: 4),

                            // ── 担当探偵（タップで探偵タブへ） ──
                            _RoleRow(role: role, onTap: onTapRole),
                            const SizedBox(height: 12),

                            // ── 週間ヒートマップ + 連続日数 ─────
                            // Row + Spacer ではなく Wrap を使う。
                            // 1行に収まるときは spaceBetween が Spacer と同じ見た目になり、
                            // 文字サイズを上げて収まらなくなったときは overflow せず折り返す。
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 12,
                              runSpacing: 10,
                              children: [
                                _WeekHeatmap(flags: weekFlags, today: today),
                                Text(
                                  _streakLabel,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: c.gold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
    );
  }
}

// 今日の1段（日々の記録 / 事件簿）。行ごとにタップでき、その段だけを開く。
class _StepRow extends StatelessWidget {
  final int index;
  final String title;
  final String status;
  final bool done;
  final String? preview;
  final VoidCallback onTap;

  const _StepRow({
    required this.index,
    required this.title,
    required this.status,
    required this.done,
    required this.onTap,
    this.preview,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        // タップ領域を 48dp 以上に保つための余白
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 済んだ段は gold の塗り＋onAccent、まだの段は枠だけ
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? c.gold : Colors.transparent,
                border: Border.all(color: c.gold),
              ),
              child: done
                  ? Icon(Icons.check, size: 14, color: c.onAccent)
                  : Text(
                      '$index',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: c.gold,
                      ),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        status,
                        style: TextStyle(fontSize: 12, color: c.textSecondary),
                      ),
                    ],
                  ),
                  if (preview != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      preview!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 20, color: c.gold),
          ],
        ),
      ),
    );
  }
}

// 読み込み中のプレースホルダ。
// 描画後のレイアウトジャンプを避けるため、実データ時とおおよそ同じ高さを確保する。
class _TodayCardPlaceholder extends StatelessWidget {
  const _TodayCardPlaceholder();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: 180,
      child: Center(
        child: CircularProgressIndicator(color: c.gold, strokeWidth: 2),
      ),
    );
  }
}

// 担当探偵の行。タップで探偵の指名（RoleSelectPage）へ。
class _RoleRow extends StatelessWidget {
  final Role role;
  final VoidCallback onTap;

  const _RoleRow({required this.role, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        // タップ領域を 48dp 以上に保つための余白（アイコン自体は小さくてよい）
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(Icons.person_search, size: 18, color: c.gold),
            const SizedBox(width: 8),
            Text('担当', style: TextStyle(fontSize: 12, color: c.textSecondary)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                role.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: c.textPrimary,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: c.gold),
          ],
        ),
      ),
    );
  }
}

// 直近7日の記録有無を点で示すヒートマップ。末尾が今日。
class _WeekHeatmap extends StatelessWidget {
  final List<bool> flags;
  final DateTime today;

  const _WeekHeatmap({required this.flags, required this.today});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(flags.length, (i) {
        // Duration ではなく DateTime の日フィールド演算で遡る（夏時間対策）
        final d = DateTime(
          today.year,
          today.month,
          today.day - (flags.length - 1 - i),
        );
        final on = flags[i];
        return Padding(
          padding: EdgeInsets.only(right: i == flags.length - 1 ? 0 : 7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: on ? c.gold : Colors.transparent,
                  border: on
                      ? null
                      : Border.all(color: c.cardBorder, width: 1.2),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _weekdayJa[d.weekday - 1],
                style: TextStyle(fontSize: 9, color: c.textSecondary),
              ),
            ],
          ),
        );
      }),
    );
  }
}

// 直近の事件が0件のときの表示
class _EmptyRecent extends StatelessWidget {
  const _EmptyRecent();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        border: Border.all(color: c.cardBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          Icon(Icons.folder_open, size: 36, color: c.cardBorder),
          const SizedBox(height: 10),
          Text(
            'まだ過去の事件はありません',
            style: TextStyle(fontSize: 13, color: c.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// 自己分析（依頼人の人物像）へのタイル
//
// CaseArchiveTile と同じ「左端ゴールド帯＋見出し＋副文＋矢印」の書類風にして、
// 直近の事件リストと並んだときに同じ資料棚に見えるようにする。
// 未登録のときは何を登録する場所なのかが分かる副文を出す。
// ──────────────────────────────────────────────────────────────
class _SelfAnalysisTile extends StatelessWidget {
  final bool loading;
  final SelfAnalysis selfAnalysis;
  final VoidCallback onTap;

  const _SelfAnalysisTile({
    required this.loading,
    required this.selfAnalysis,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final type = mbtiTypeFor(selfAnalysis.mbti);
    final String subtitle;
    if (loading) {
      subtitle = '照会中…';
    } else if (type != null) {
      subtitle = '${type.key}（${type.label}）';
    } else {
      subtitle = '依頼人の人物像はまだ白紙だ。';
    }

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
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 左端のゴールドアクセントボーダー
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: c.gold,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    bottomLeft: Radius.circular(4),
                  ),
                ),
              ),

              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.psychology_outlined,
                            size: 14,
                            color: c.gold,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '自己分析',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: c.gold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: c.textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 右端の矢印アイコン
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Icon(Icons.chevron_right, color: c.gold, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 追跡中の事件が1件も無いとき・読み込み中に出すタイル。
//
// GoalCaseTile と共通化していないのは、あちらが「既にある事件1件」を描く部品で、
// こちらは行き先の案内だから。相談室ハブの空状態は「＋ 新しい事件を立てる」が
// 主役で見せ方が違うため、空状態は画面ごとに持つ。
class _GoalNoticeTile extends StatelessWidget {
  final String message;
  final VoidCallback onTap;

  const _GoalNoticeTile({required this.message, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
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
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: c.gold,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    bottomLeft: Radius.circular(4),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.flag_outlined, size: 14, color: c.gold),
                          const SizedBox(width: 6),
                          Text(
                            '追跡中の事件',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: c.gold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: c.textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Icon(Icons.chevron_right, color: c.gold, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
