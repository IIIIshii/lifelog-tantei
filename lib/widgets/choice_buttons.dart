import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

// 選択肢をボタンで提示するウィジェット。
// 会話の画面（聴取・相談室）が同じ見た目の選択肢を出すために共有する。

// 横に折り返して並べる選択肢ボタン。2択・短いラベル向け。
class ChoiceButtons extends StatelessWidget {
  final List<String> choices;
  final ValueChanged<String> onSelect;

  const ChoiceButtons({
    super.key,
    required this.choices,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: choices.map((choice) {
        return ElevatedButton(
          onPressed: () => onSelect(choice),
          style: ElevatedButton.styleFrom(
            backgroundColor: c.gold,
            foregroundColor: c.onAccent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          child: Text(choice),
        );
      }).toList(),
    );
  }
}

// 縦に積む選択肢ボタン。ラベルが長く、横並びだと読みにくいとき向け。
class StackedChoiceButtons extends StatelessWidget {
  final List<String> choices;
  final ValueChanged<String> onSelect;

  const StackedChoiceButtons({
    super.key,
    required this.choices,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: choices.map((choice) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: ElevatedButton(
            onPressed: () => onSelect(choice),
            style: ElevatedButton.styleFrom(
              backgroundColor: c.gold,
              foregroundColor: c.onAccent,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: Text(choice, textAlign: TextAlign.center),
          ),
        );
      }).toList(),
    );
  }
}
