import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../models/goal.dart';

// 目標の段階の一覧。番号・タイトル・期限を並べ、達成済みは印を付けて沈める。
//
// 相談室の見立てカードと、目標の記録一覧の見出しの2か所で同じものを出すため、
// ここに一本化している。今の段階（未達成のうち最初のもの）だけ太字にして、
// 「今どこにいるか」が一目で分かるようにする。
class GoalStepList extends StatelessWidget {
  final List<GoalStep> steps;

  const GoalStepList({super.key, required this.steps});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    String? currentId;
    for (final step in steps) {
      if (!step.isDone) {
        currentId = step.id;
        break;
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          _StepRow(
            number: i + 1,
            step: steps[i],
            current: steps[i].id == currentId,
            c: c,
          ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  final int number;
  final GoalStep step;
  final bool current;
  final AppColors c;

  const _StepRow({
    required this.number,
    required this.step,
    required this.current,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: step.isDone
                ? Icon(Icons.check_circle, size: 16, color: c.gold)
                : Text(
                    '$number.',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: c.gold,
                    ),
                  ),
          ),
          Expanded(
            child: Text(
              step.title,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                fontWeight: current ? FontWeight.bold : FontWeight.normal,
                color: step.isDone ? c.textSecondary : c.textPrimary,
              ),
            ),
          ),
          if (step.deadline.isNotEmpty || step.isDone) ...[
            const SizedBox(width: 8),
            Text(
              step.isDone ? '達成 ${step.doneAt}' : step.deadline,
              style: TextStyle(fontSize: 11, color: c.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
