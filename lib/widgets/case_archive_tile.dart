import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

// ──────────────────────────────────────────────────────────────
// 事件簿1件分の表示ウィジェット
//
// 左端ゴールドボーダー＋日付ゴールド表示のファイル風デザイン。
// 事件簿アーカイブ（DiaryListPage）とホームの「直近の事件」で共用する。
// 同じ意味を持つ行が2画面で別実装にならないよう、ここに一本化している。
// ──────────────────────────────────────────────────────────────
class CaseArchiveTile extends StatelessWidget {
  final String date; // YYYY-MM-DD形式
  final String diary; // 日記本文（プレビュー用）
  final VoidCallback onTap;

  const CaseArchiveTile({
    super.key,
    required this.date,
    required this.diary,
    required this.onTap,
  });

  // YYYY-MM-DD → YYYY年MM月DD日 に整形する
  String _formatDate(String raw) {
    final parts = raw.split('-');
    if (parts.length != 3) return raw;
    return '${parts[0]}年${parts[1]}月${parts[2]}日';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final preview = diary.trim().isEmpty ? '（本文なし）' : diary;
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

              // 日付と日記プレビュー
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 日付（ゴールド太字でアーカイブ番号のように見せる）
                      Row(
                        children: [
                          Icon(Icons.folder_open, size: 14, color: c.gold),
                          const SizedBox(width: 6),
                          Text(
                            _formatDate(date),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: c.gold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // 日記本文のプレビュー（2行まで）
                      Text(
                        preview,
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
