import 'package:flutter/material.dart';
import '../core/theme/detective_theme.dart';

// 生成された日記を「事件報告書」として会話リストの末尾に表示するカードウィジェット
// ゴールドの枠線・ヘッダー・CLOSEDバッジで公式書類のような見た目を演出する
class DiaryCard extends StatelessWidget {
  final String diary; // 表示する日記テキスト

  const DiaryCard({super.key, required this.diary});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: DetectiveTheme.cardBg,
        borderRadius: BorderRadius.circular(4),
        // ゴールドの枠線で「重要書類」感を表現する
        border: Border.all(color: DetectiveTheme.gold, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── ヘッダー行 ──────────────────────────────────────
          // 左: 「事件報告書」ラベル / 右: 「CLOSED」バッジ
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              // ヘッダーと本文をゴールドの区切り線で分ける
              border:
                  Border(bottom: BorderSide(color: DetectiveTheme.gold)),
            ),
            child: Row(
              children: [
                const Icon(Icons.description,
                    color: DetectiveTheme.gold, size: 16),
                const SizedBox(width: 6),
                const Text(
                  '事件報告書',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: DetectiveTheme.gold,
                    letterSpacing: 1.0,
                  ),
                ),
                const Spacer(),
                // CLOSEDバッジ（英字でノワール感を強調）
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    border: Border.all(color: DetectiveTheme.gold),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: const Text(
                    'CLOSED',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: DetectiveTheme.gold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── 日記本文 ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              diary,
              style: const TextStyle(
                fontSize: 14,
                color: DetectiveTheme.textPrimary,
                height: 1.8, // 行間を広めにとって読みやすくする
              ),
            ),
          ),
        ],
      ),
    );
  }
}
