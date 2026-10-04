import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

// ──────────────────────────────────────────────────────────────
// 「未着手 / 記録済み」バッジ。
//
// DiaryCard の CLOSED バッジと同じ枠線スタイルにして書類感を揃える。
// もともと home_page.dart のプライベートウィジェットだったものを、
// 本日の事件カードと目標カード（GoalCaseTile）の2箇所が使うようになったため
// 切り出した。見た目・挙動は移設前のまま変えていない。
// ──────────────────────────────────────────────────────────────
class StatusBadge extends StatelessWidget {
  final bool done;

  const StatusBadge({super.key, required this.done});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: done ? c.gold.withValues(alpha: 0.12) : Colors.transparent,
        border: Border.all(color: c.gold),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        done ? '記録済み' : '未着手',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: c.gold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
