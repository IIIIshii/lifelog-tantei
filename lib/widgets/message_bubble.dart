import 'package:flutter/material.dart';
import '../core/theme/detective_theme.dart';

// 会話の1メッセージを尋問ログ風に表示するウィジェット
// AI（探偵）は左寄せ・クリーム背景、ユーザー（証言）は右寄せ・薄茶背景で表示する
class MessageBubble extends StatelessWidget {
  final String role; // 'ai' または 'user'
  final String text;

  const MessageBubble({super.key, required this.role, required this.text});

  @override
  Widget build(BuildContext context) {
    final isAI = role == 'ai';

    return Align(
      alignment: isAI ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        // 吹き出しの横幅は画面の75%まで（長文でも画面からはみ出ないように）
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Column(
          crossAxisAlignment:
              isAI ? CrossAxisAlignment.start : CrossAxisAlignment.end,
          children: [
            // ── 発言者ラベル（探偵 / 証言）──────────────────────
            // 虫眼鏡アイコン付きの「探偵」ラベルでノワール感を演出する
            Padding(
              padding: const EdgeInsets.only(bottom: 3, left: 4, right: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isAI) ...[
                    const Icon(Icons.search,
                        size: 11, color: DetectiveTheme.gold),
                    const SizedBox(width: 3),
                  ],
                  Text(
                    isAI ? '探偵' : '証言',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: DetectiveTheme.gold,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            ),

            // ── メッセージ本体 ────────────────────────────────────
            // AI: 左端ゴールドボーダー / User: 右端ゴールドボーダーで区別する
            IntrinsicHeight(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // AI側の左端アクセントボーダー
                  if (isAI)
                    Container(
                      width: 3,
                      decoration: const BoxDecoration(
                        color: DetectiveTheme.gold,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(4),
                          bottomLeft: Radius.circular(4),
                        ),
                      ),
                    ),

                  // テキスト本体
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        // AI: クリーム / User: 薄茶で視覚的に区別する
                        color: isAI
                            ? DetectiveTheme.cardBg
                            : const Color(0xFFE8DDD0),
                        border: Border.all(color: DetectiveTheme.cardBorder),
                        borderRadius: BorderRadius.only(
                          // ボーダーと隣接する角は丸めない（継ぎ目を自然に見せる）
                          topLeft: isAI
                              ? Radius.zero
                              : const Radius.circular(12),
                          topRight: isAI
                              ? const Radius.circular(12)
                              : Radius.zero,
                          bottomLeft: const Radius.circular(12),
                          bottomRight: const Radius.circular(12),
                        ),
                      ),
                      child: Text(
                        text,
                        style: const TextStyle(
                          fontSize: 14,
                          color: DetectiveTheme.textPrimary,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),

                  // User側の右端アクセントボーダー
                  if (!isAI)
                    Container(
                      width: 3,
                      decoration: const BoxDecoration(
                        color: DetectiveTheme.gold,
                        borderRadius: BorderRadius.only(
                          topRight: Radius.circular(4),
                          bottomRight: Radius.circular(4),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
