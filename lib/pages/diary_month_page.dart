import 'package:flutter/material.dart';
import '../core/streak.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/detective_text_styles.dart';
import '../widgets/case_archive_tile.dart';

const _weekdayLabels = ['日', '月', '火', '水', '木', '金', '土'];
const _cellHeight = 48.0;

// 1か月分の事件簿を、カレンダーと選択日のプレビューで見せるページ
//
// 日記がある日には虫眼鏡を出し、タップするとその日が選択されて下のプレビューが入れ替わる。
// 小さい端末ではプレビューが画面外に出て、日付を押しても何も起きないように見えるため、
// 選択のたびにプレビューが見える位置まで自動でスクロールする。
//
// Firestore に直接つながず Stream と遷移コールバックを受け取るのは、
// Firebase を初期化せずにウィジェットテストできるようにするため。
class DiaryMonthPage extends StatefulWidget {
  final int year;
  final int month;

  // 日付（YYYY-MM-DD）→日記本文。他の月が混ざっていてもよい（この月だけ使う）
  final Stream<Map<String, String>> entries;

  // プレビューのタップで日記詳細へ遷移する処理（呼び出し側が持つ）
  final void Function(String date, String diary) onOpenDetail;

  const DiaryMonthPage({
    super.key,
    required this.year,
    required this.month,
    required this.entries,
    required this.onOpenDetail,
  });

  @override
  State<DiaryMonthPage> createState() => _DiaryMonthPageState();
}

class _DiaryMonthPageState extends State<DiaryMonthPage> {
  final _previewKey = GlobalKey();

  // ユーザーが選んだ日。null の間、または選んだ日の記録が消えた場合は月内の最新日を使う
  String? _selected;

  void _select(String key) {
    setState(() => _selected = key);
    // プレビューが差し替わった後のレイアウトを待ってからスクロールする。
    // すでに見えている場合は動かさない（keepVisibleAtEnd は最小限だけ動かす）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _previewKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      Scrollable.ensureVisible(
        ctx,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final prefix = dateKey(
      DateTime(widget.year, widget.month, 1),
    ).substring(0, 8);

    return Scaffold(
      backgroundColor: c.background,
      // 読み込み中・エラー時も戻るボタンを出すため、AppBar は StreamBuilder の外に置く
      appBar: _buildAppBar(c),
      body: StreamBuilder<Map<String, String>>(
        stream: widget.entries,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('エラー: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator(color: c.gold));
          }

          final monthEntries = {
            for (final e in snapshot.data!.entries)
              if (e.key.startsWith(prefix)) e.key: e.value,
          };
          final latest = monthEntries.isEmpty
              ? null
              : (monthEntries.keys.toList()..sort()).last;
          final selected = monthEntries.containsKey(_selected)
              ? _selected
              : latest;

          return SingleChildScrollView(
            child: Column(
              children: [
                _buildCalendar(c, monthEntries, selected),
                KeyedSubtree(
                  key: _previewKey,
                  child: _buildPreview(c, monthEntries, selected),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(AppColors c) {
    return AppBar(
      backgroundColor: c.appBarBg,
      foregroundColor: c.appBarFg,
      elevation: 0,
      toolbarHeight: 64,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.month}月の事件簿',
            style: DetectiveTextStyles.appBarTitle(color: c.appBarFg),
          ),
          const SizedBox(height: 2),
          Text(
            '― ${widget.year}年 ―',
            style: DetectiveTextStyles.appBarSubtitle(color: c.appBarSubtitle),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendar(
    AppColors c,
    Map<String, String> monthEntries,
    String? selected,
  ) {
    // 月初の曜日（日曜=0）。DateTime.weekday は月曜=1…日曜=7
    final lead = DateTime(widget.year, widget.month, 1).weekday % 7;
    // 翌月0日 = 当月末日。うるう年の2月29日も暦に任せる
    final daysInMonth = DateTime(widget.year, widget.month + 1, 0).day;
    final weeks = ((lead + daysInMonth) / 7).ceil();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        children: [
          Row(
            children: [
              for (final label in _weekdayLabels)
                Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: TextStyle(fontSize: 11, color: c.textSecondary),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (var w = 0; w < weeks; w++)
            Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: _buildCell(
                      c,
                      w * 7 + i - lead + 1,
                      daysInMonth,
                      monthEntries,
                      selected,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  // day が月の範囲外（月初前・月末後の空きマス）なら空のセルを返す
  Widget _buildCell(
    AppColors c,
    int day,
    int daysInMonth,
    Map<String, String> monthEntries,
    String? selected,
  ) {
    if (day < 1 || day > daysInMonth) {
      return const SizedBox(height: _cellHeight);
    }

    final key = dateKey(DateTime(widget.year, widget.month, day));
    final hasEntry = monthEntries.containsKey(key);
    final isSelected = key == selected;
    final fg = isSelected ? c.onAccent : c.textPrimary;

    final cell = Container(
      height: _cellHeight,
      decoration: BoxDecoration(
        color: isSelected ? c.gold : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$day',
            style: TextStyle(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: fg,
            ),
          ),
          const SizedBox(height: 2),
          // 日記がない日も同じ高さを確保し、数字の縦位置を揃える
          SizedBox(
            height: 12,
            child: hasEntry
                ? Icon(
                    Icons.search,
                    size: 12,
                    color: isSelected ? c.onAccent : c.gold,
                  )
                : null,
          ),
        ],
      ),
    );

    // 日記がない日は押しても何も起きない（選択もしない）
    if (!hasEntry) return cell;
    return Semantics(
      button: true,
      selected: isSelected,
      label: '${widget.month}月$day日、事件簿あり',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _select(key),
        child: cell,
      ),
    );
  }

  Widget _buildPreview(
    AppColors c,
    Map<String, String> monthEntries,
    String? selected,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      child: selected == null
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'この月の記録はありません',
                style: TextStyle(color: c.textSecondary, fontSize: 14),
              ),
            )
          : CaseArchiveTile(
              date: selected,
              diary: monthEntries[selected]!,
              onTap: () =>
                  widget.onOpenDetail(selected, monthEntries[selected]!),
            ),
    );
  }
}
