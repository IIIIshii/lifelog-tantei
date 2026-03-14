import 'package:flutter/material.dart';
import '../core/theme/detective_theme.dart';

// ユーザーが証言（テキスト）を入力して送信するための入力エリアウィジェット
// 羊皮紙風の塗りつぶしフィールド＋ゴールドの丸い送信ボタンで証言台を表現する
class InputArea extends StatelessWidget {
  final TextEditingController controller;
  final void Function(String) onSubmit; // 送信時に呼ばれるコールバック

  const InputArea(
      {super.key, required this.controller, required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    return Container(
      // 入力エリア全体に薄いトップボーダーを付けてチャット領域と区切る
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      decoration: const BoxDecoration(
        color: DetectiveTheme.cardBg,
        border: Border(top: BorderSide(color: DetectiveTheme.cardBorder)),
      ),
      child: Row(
        children: [
          // ── テキストフィールド ──────────────────────────────
          // 塗りつぶしの羊皮紙背景でノワール感を演出する
          Expanded(
            child: TextField(
              controller: controller,
              style: const TextStyle(
                fontSize: 14,
                color: DetectiveTheme.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: '証言を入力...',
                hintStyle: const TextStyle(
                  color: DetectiveTheme.textSecondary,
                  fontSize: 13,
                ),
                filled: true,
                fillColor: DetectiveTheme.background,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                // 通常時: カードボーダー色
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide:
                      const BorderSide(color: DetectiveTheme.cardBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide:
                      const BorderSide(color: DetectiveTheme.cardBorder),
                ),
                // フォーカス時: ゴールドに変化させてアクティブ状態を示す
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(
                      color: DetectiveTheme.gold, width: 1.5),
                ),
              ),
              onSubmitted: onSubmit, // キーボードのEnterキーでも送信できる
            ),
          ),

          const SizedBox(width: 10),

          // ── 送信ボタン ─────────────────────────────────────
          // ゴールドの丸いボタンで探偵テーマに統一する
          GestureDetector(
            onTap: () => onSubmit(controller.text),
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: DetectiveTheme.gold,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.arrow_forward,
                  color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
