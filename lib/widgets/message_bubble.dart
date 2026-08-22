import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import 'typewriter_text.dart';

// 会話の1メッセージを尋問ログ風に表示するウィジェット
// AI（探偵）は左寄せ・クリーム背景、ユーザー（証言）は右寄せ・薄茶背景で表示する
class MessageBubble extends StatelessWidget {
  final String role; // 'ai' または 'user'
  final String text;

  // タイプライター表示させるか。AIの発言かつ「まだ流していない」ものだけ true にする。
  // 表示済みの発言まで true にすると、スクロールで画面外に出て戻るたびに
  // ListView.builder が作り直して再生し直してしまう。
  final bool animate;

  // タイプが完了した（またはタップでスキップされた）ときに呼ばれる
  final VoidCallback? onAnimationFinished;

  const MessageBubble({
    super.key,
    required this.role,
    required this.text,
    this.animate = false,
    this.onAnimationFinished,
  });

  @override
  Widget build(BuildContext context) {
    final isAI = role == 'ai';
    final c = context.colors;
    final bodyStyle = TextStyle(
      fontSize: 14,
      color: c.textPrimary,
      height: 1.5,
    );

    return Align(
      alignment: isAI ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        // 吹き出しの横幅は画面の75%まで（長文でも画面からはみ出ないように）
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Column(
          crossAxisAlignment: isAI
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.end,
          children: [
            // ── 発言者ラベル（探偵 / 証言）──────────────────────
            // 虫眼鏡アイコン付きの「探偵」ラベルでノワール感を演出する
            Padding(
              padding: const EdgeInsets.only(bottom: 3, left: 4, right: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isAI) ...[
                    Icon(Icons.search, size: 11, color: c.gold),
                    const SizedBox(width: 3),
                  ],
                  Text(
                    isAI ? '探偵' : '証言',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: c.gold,
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
                      decoration: BoxDecoration(
                        color: c.gold,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(4),
                          bottomLeft: Radius.circular(4),
                        ),
                      ),
                    ),

                  // テキスト本体
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        // AI: クリーム / User: 薄茶で視覚的に区別する
                        color: isAI ? c.bubbleAi : c.bubbleUser,
                        border: Border.all(color: c.cardBorder),
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
                      // 流し終えた発言とユーザーの証言は素の Text で描画する。
                      // タイプ対象は常に1件だけなので、履歴を遡っても再生されない。
                      child: isAI && animate
                          ? TypewriterText(
                              text: text,
                              style: bodyStyle,
                              onFinished: onAnimationFinished,
                            )
                          : Text(text, style: bodyStyle),
                    ),
                  ),

                  // User側の右端アクセントボーダー
                  if (!isAI)
                    Container(
                      width: 3,
                      decoration: BoxDecoration(
                        color: c.gold,
                        borderRadius: const BorderRadius.only(
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
