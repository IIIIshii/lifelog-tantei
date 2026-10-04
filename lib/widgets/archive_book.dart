import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/detective_text_styles.dart';
import '../models/archive_month.dart';

// ──────────────────────────────────────────────────────────────
// 事件簿アーカイブの本棚に並ぶ「1か月分の本」
//
// 面・枠線・文字は CaseArchiveTile と同じカード系トークンで描く。
// chartPalette を表紙全面に塗らないのは、ダーク系テーマのパレットが
// 明るいパステル調で、本棚全体が浮いてしまうため。パレットは背表紙の帯だけに使い、
// 月ごとの見分けを担わせる（本の面はコントラストが検証済みのトークンに任せる）。
// サイズは親（GridView 等）が決める。
// ──────────────────────────────────────────────────────────────
class ArchiveBook extends StatelessWidget {
  final ArchiveMonth month;
  final VoidCallback onTap;

  const ArchiveBook({super.key, required this.month, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // 月番号でパレットを巡回させ、何年でも同じ月は同じ背表紙の色にする
    final spine = c.chartPalette[(month.month - 1) % c.chartPalette.length];

    return Semantics(
      button: true,
      label: '${month.year}年${month.month}月の事件簿、${month.count}件',
      excludeSemantics: true,
      child: Material(
        color: c.cardBg,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(6)),
          side: BorderSide(color: c.cardBorder),
        ),
        child: InkWell(
          onTap: onTap,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 背表紙
              Container(width: 16, color: spine),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.search, size: 26, color: c.gold),
                    const SizedBox(height: 6),
                    Text(
                      '${month.year}',
                      style: DetectiveTextStyles.caseNumber(
                        color: c.textSecondary,
                      ).copyWith(fontSize: 11, letterSpacing: 2),
                    ),
                    Text(
                      '${month.month}月',
                      style: DetectiveTextStyles.appBarTitle(
                        color: c.textPrimary,
                      ).copyWith(fontSize: 28, letterSpacing: 0),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${month.count}件の事件',
                      style: DetectiveTextStyles.cardSubtitle(
                        color: c.textSecondary,
                      ).copyWith(fontSize: 11),
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
