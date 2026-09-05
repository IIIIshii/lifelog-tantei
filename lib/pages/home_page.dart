import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/streak.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/detective_text_styles.dart';
import '../roles/roles.dart';
import '../services/firestore_service.dart';
import '../widgets/case_archive_tile.dart';
import 'diary_detail_page.dart';
import 'diary_page.dart';

// ストリーク算出とヒートマップに使う遡り日数。
// 7日ぶんのヒートマップには足りるが、連続日数はここが上限になるため余裕を持たせている。
const int _lookbackDays = 30;

// ホーム（事務所）タブに表示する「直近の事件」の最大件数。
// これ以上は事件簿アーカイブタブの仕事なので、ホームでは3件に留める。
const int _recentPreviewCount = 3;

const List<String> _weekdayJa = ['月', '火', '水', '木', '金', '土', '日'];

// ──────────────────────────────────────────────────────────────
// ホーム画面（事務所タブ）
//
// メニューの羅列をやめ、「本日の事件」ヒーローカードで状態を最初に見せる構成。
// 主要動線（日記をつける）は MainShell 側の Extended FAB が担うため、
// ここでは同じ行き先をカード全体のタップにも持たせている
// （FABに手が届かない両手操作のユーザー向けの重複導線）。
// ──────────────────────────────────────────────────────────────
class HomePage extends StatefulWidget {
  final String uid;

  /// MainShell が値を進めるたびに再読込するシグナル。
  /// タブは IndexedStack で保持され破棄されないため、他タブでの変更
  /// （探偵の指名、デモデータ投入など）を反映するにはこの明示的な合図が要る。
  final ValueListenable<int> refreshSignal;

  /// 今日の記録有無を MainShell へ伝える出力。FAB のラベル切替に使う。
  /// 読み込み前は null。
  final ValueNotifier<bool?> todayDone;

  /// ヒーローカードの「担当探偵」行から探偵タブへ移動するためのコールバック。
  /// タブの index は MainShell の関心事なので、ここでは持たない。
  final VoidCallback onOpenRoleTab;

  const HomePage({
    super.key,
    required this.uid,
    required this.refreshSignal,
    required this.todayDone,
    required this.onOpenRoleTab,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FirestoreService _firestore = FirestoreService();

  bool _loading = true;
  bool _failed = false;
  Role _role = roleFor(null);
  Set<String> _written = const {};
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

  // ヒーローカードと直近リストに必要なデータをまとめて取得する。
  // 「今日書いたか」は getRecentEntries の結果に今日の日付が含まれるかで判定できるため、
  // getTodayDiary を別途呼ばずに Firestore の読み取り回数を増やさない。
  Future<void> _load() async {
    final entriesFuture = _firestore.getRecentEntries(widget.uid, _lookbackDays);
    final settingsFuture = _firestore.getUserSettings(widget.uid);

    try {
      final entries = await entriesFuture;
      final settings = await settingsFuture;
      if (!mounted) return;

      // diary が非 null のものだけを「記録済み」とみなす。
      // 会話の途中で終わったドキュメントも entries には存在するため、
      // 事件簿アーカイブの絞り込み（diary_list_page）と基準を揃える。
      final withDiary = entries.where((e) => e.value['diary'] != null).toList()
        ..sort((a, b) => b.key.compareTo(a.key));

      final todayKey = dateKey(DateTime.now());
      String? todayDiary;
      for (final e in withDiary) {
        if (e.key == todayKey) {
          todayDiary = e.value['diary'] as String;
          break;
        }
      }

      setState(() {
        _written = withDiary.map((e) => e.key).toSet();
        _recent = withDiary.where((e) => e.key != todayKey).toList();
        _todayDiary = todayDiary;
        _role = roleFor(settings.selectedRole);
        _loading = false;
        _failed = false;
      });
      widget.todayDone.value = todayDiary != null;
    } catch (_) {
      if (!mounted) return;
      // 失敗しても RefreshIndicator で引き直せるので、画面は保ったまま印だけ出す
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  // 本日の事件カードのタップ：記録済みなら詳細、未記録なら対話画面へ
  void _openToday() {
    final diary = _todayDiary;
    final route = diary != null
        ? MaterialPageRoute<void>(
            builder: (_) => DiaryDetailPage(
              date: dateKey(DateTime.now()),
              diary: diary,
              uid: widget.uid,
              firestore: _firestore,
            ),
          )
        : MaterialPageRoute<void>(builder: (_) => const DiaryPage());
    Navigator.push(context, route).then((_) => _load());
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
              style: DetectiveTextStyles.appBarSubtitle(color: c.appBarSubtitle),
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
            // ── 本日の事件（ヒーロー） ──────────────────────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              sliver: SliverToBoxAdapter(
                child: _TodayCaseCard(
                  loading: _loading,
                  today: today,
                  todayDiary: _todayDiary,
                  role: _role,
                  weekFlags: recentDayFlags(_written, today, 7),
                  streak: calcStreak(_written, today),
                  onTapCard: _openToday,
                  onTapRole: widget.onOpenRoleTab,
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

            // ── 直近の事件 ──────────────────────────────────
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(20, 28, 20, 12),
              sliver: SliverToBoxAdapter(child: _SectionLabel('直近の事件')),
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
                    final diary = entry.value['diary'] as String;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: CaseArchiveTile(
                        date: entry.key,
                        diary: diary,
                        onTap: () =>
                            Navigator.push(
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
// 本日の事件カード（ヒーロー領域）
//
// 既存カードのデザイン言語（cardBg + cardBorder 枠 + 左端ゴールド4px縦帯）を
// 踏襲しつつ、状態バッジ・担当探偵・週間ヒートマップを1枚にまとめる。
// ──────────────────────────────────────────────────────────────
class _TodayCaseCard extends StatelessWidget {
  final bool loading;
  final DateTime today;
  final String? todayDiary;
  final Role role;
  final List<bool> weekFlags; // 7件、末尾が今日
  final int streak;
  final VoidCallback onTapCard;
  final VoidCallback onTapRole;

  const _TodayCaseCard({
    required this.loading,
    required this.today,
    required this.todayDiary,
    required this.role,
    required this.weekFlags,
    required this.streak,
    required this.onTapCard,
    required this.onTapRole,
  });

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
    final done = todayDiary != null;

    return Material(
      color: c.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(4)),
        side: BorderSide(color: c.cardBorder),
      ),
      child: InkWell(
        onTap: loading ? null : onTapCard,
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
                  padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                  child: loading
                      ? const _TodayCardPlaceholder()
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── 見出し行 ───────────────────────
                            Row(
                              children: [
                                Icon(Icons.description, size: 16, color: c.gold),
                                const SizedBox(width: 6),
                                // Spacer ではなく Expanded にする。
                                // 端末の文字サイズを上げるとラベルとバッジが
                                // 横幅を食い合って overflow するため。
                                Expanded(
                                  child: Text(
                                    '本日の事件',
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
                                _StatusBadge(done: done),
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

                            // ── 記録済みなら本文プレビュー ─────
                            if (done) ...[
                              const SizedBox(height: 8),
                              Text(
                                todayDiary!.trim().isEmpty
                                    ? '（本文なし）'
                                    : todayDiary!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.6,
                                  color: c.textSecondary,
                                ),
                              ),
                            ] else ...[
                              const SizedBox(height: 6),
                              Text(
                                'まだ調書は白紙のままだ。',
                                style: DetectiveTextStyles.catchphrase(
                                  color: c.textSecondary,
                                ),
                              ),
                            ],

                            const SizedBox(height: 14),
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

// 「未着手 / 記録済み」バッジ。
// DiaryCard の CLOSED バッジと同じ枠線スタイルにして書類感を揃える。
class _StatusBadge extends StatelessWidget {
  final bool done;

  const _StatusBadge({required this.done});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: done ? c.gold.withValues(alpha: 0.12) : Colors.transparent,
        border: Border.all(color: c.gold),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        done ? '記録済み' : '未着手',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: c.gold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

// 担当探偵の行。カード全体の InkWell の内側に入れ子にして、
// ここだけ探偵タブへ飛ばす（内側の InkWell がタップを吸収する）。
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

// セクション見出し。ゴールドの小見出し＋罫線で書類の章立てに見せる。
class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Icon(Icons.folder_open, size: 14, color: c.gold),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
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
        const SizedBox(width: 10),
        Expanded(child: Divider(height: 1, color: c.cardBorder)),
      ],
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
