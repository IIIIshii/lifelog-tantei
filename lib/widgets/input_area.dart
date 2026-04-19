import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

// ユーザーが証言（テキスト）を入力して送信するための入力エリアウィジェット
// 羊皮紙風の塗りつぶしフィールド＋ゴールドの丸い送信ボタンで証言台を表現する
class InputArea extends StatelessWidget {
  final TextEditingController controller;
  final void Function(String) onSubmit; // 送信時に呼ばれるコールバック

  const InputArea(
      {super.key, required this.controller, required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      // 入力エリア全体に薄いトップボーダーを付けてチャット領域と区切る
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      decoration: BoxDecoration(
        color: c.cardBg,
        border: Border(top: BorderSide(color: c.cardBorder)),
      ),
      child: Row(
        children: [
          // ── テキストフィールド ──────────────────────────────
          // 塗りつぶしの羊皮紙背景でノワール感を演出する
          Expanded(
            child: TextField(
              controller: controller,
              style: TextStyle(
                fontSize: 14,
                color: c.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: '証言を入力...',
                hintStyle: TextStyle(
                  color: c.textSecondary,
                  fontSize: 13,
                ),
                filled: true,
                fillColor: c.background,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                // 通常時: カードボーダー色
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: c.cardBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: c.cardBorder),
                ),
                // フォーカス時: ゴールドに変化させてアクティブ状態を示す
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: c.gold, width: 1.5),
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
              decoration: BoxDecoration(
                color: c.gold,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.arrow_forward,
                  color: c.appBarFg, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
