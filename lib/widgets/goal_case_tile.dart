import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/detective_text_styles.dart';
import '../models/goal.dart';
import 'status_badge.dart';

// ──────────────────────────────────────────────────────────────
// 追跡中の事件（目標）1件の行
//
// CaseArchiveTile と同じ「左端ゴールド帯＋見出し＋本文＋右端アイコン」の書類風。
// ホーム（事務所タブ）と相談室ハブの両方がこの形で目標を並べるので、
// 同じ意味を持つ行が2画面で別実装にならないよう、ここに一本化している。
//
// 目標が1件だけだった頃、この部品はホームの中で「読み込み中・未設定・設定済み」の
// 3状態を1枚で受け持っていた。複数件になって設定済みの行だけが繰り返されるように
// なったため、ここは既存の目標1件の描画だけを担当する。
// 読み込み中と未設定の見せ方は画面ごとに意味が違う（ホームは「立てる場所がある」ことを
// 伝える1枚、ハブは「＋新しい事件を立てる」が主役）ので、各ページに置いたままにする。
// ──────────────────────────────────────────────────────────────
class GoalCaseTile extends StatelessWidget {
  final Goal goal;

  /// 今日この目標の行動項目に答えたか。
  final bool recordedToday;

  /// 見出し行に出す一言（「着手から12日 / 期限 2026-12-31」など）。
  /// null なら「追跡中の事件」を出す。事件ごとの情報が要るハブでだけ渡す。
  final String? footnote;

  final VoidCallback onTap;

  /// 非 null なら右端をメニューボタンにし、行の長押しでも同じものを開く。
  /// null なら右端はシェブロン（タップ先が1つしかない画面向け）。
  final VoidCallback? onMenu;

  const GoalCaseTile({
    super.key,
    required this.goal,
    required this.recordedToday,
    required this.onTap,
    this.footnote,
    this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final menu = onMenu;

    return Material(
      color: c.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(4)),
        side: BorderSide(color: c.cardBorder),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: menu,
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
                      _buildHeader(c),
                      const SizedBox(height: 6),
                      ..._buildBody(c),
                    ],
                  ),
                ),
              ),
              if (menu == null)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Icon(Icons.chevron_right, color: c.gold, size: 20),
                )
              else
                // 長押しだけの導線にしないのは、画面上に手がかりが何も残らず、
                // 押し続けが難しい人が操作にたどり着けなくなるため。
                IconButton(
                  onPressed: menu,
                  icon: const Icon(Icons.more_horiz, size: 20),
                  color: c.gold,
                  tooltip: '事件の操作',
                ),
            ],
          ),
        ),
      ),
    );
  }

  // 見出し行。文字サイズを上げてもバッジが押し出されないよう Wrap で折り返す。
  Widget _buildHeader(AppColors c) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.flag_outlined, size: 14, color: c.gold),
            const SizedBox(width: 6),
            Text(
              footnote ?? '追跡中の事件',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: c.gold,
              ),
            ),
          ],
        ),
        // 記録するものが無いうちはバッジを出さない（未着手と出しても行き場がない）
        if (goal.actions.isNotEmpty) StatusBadge(done: recordedToday),
      ],
    );
  }

  // 本文。毎日追う項目があればそれを、無ければ達成の基準を副文にする。
  List<Widget> _buildBody(AppColors c) {
    return [
      Text(
        goal.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: DetectiveTextStyles.cardTitle(
          color: c.textPrimary,
        ).copyWith(fontSize: 14),
      ),
      if (goal.actions.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final action in goal.actions) _ActionChip(label: action.label),
          ],
        ),
      ] else if (goal.metric.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(
          goal.metric,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: c.textSecondary, height: 1.4),
        ),
      ],
    ];
  }
}

// 行動項目1件を示す小さなチップ。
// 面には goldLight を使い、その上の文字は caseNumberFg を使う
// （gold の塗りに載せる前景が onAccent、goldLight の面に載せる前景が caseNumberFg）。
class _ActionChip extends StatelessWidget {
  final String label;

  const _ActionChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.goldLight,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: c.caseNumberFg,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
