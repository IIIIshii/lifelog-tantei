import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

// ──────────────────────────────────────────────────────────────
// セクション見出し。ゴールドの小見出し＋罫線で書類の章立てに見せる。
//
// もともと home_page.dart のプライベートウィジェットだったものを、
// 相談室ハブ（consult_hub_page.dart）と同じ章立てに見せるために切り出した。
// 見た目・挙動は移設前のまま変えていない。
//
// 設定系の SectionHeader（widgets/settings_section.dart）と分けているのは、
// あちらが「◆ 見出し＋説明文」の2行組で、こちらが「アイコン＋見出し＋罫線」の
// 1行組だから。同じ画面に混ざることはなく、使い分けは画面の性格で決まる。
// ──────────────────────────────────────────────────────────────
class SectionLabel extends StatelessWidget {
  final String text;
  final IconData icon;

  const SectionLabel(this.text, {super.key, this.icon = Icons.folder_open});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Icon(icon, size: 14, color: c.gold),
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
