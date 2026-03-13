import 'package:flutter/material.dart';

// ユーザーがテキストを入力して送信するための入力エリアウィジェット
class InputArea extends StatelessWidget {
  final TextEditingController controller;
  final void Function(String) onSubmit; // 送信時に呼ばれるコールバック

  const InputArea({super.key, required this.controller, required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: '返答を入力...',
                border: OutlineInputBorder(),
              ),
              onSubmitted: onSubmit, // キーボードのEnterキーでも送信できる
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: () => onSubmit(controller.text),
          ),
        ],
      ),
    );
  }
}
