import 'package:flutter/material.dart';

class InputArea extends StatelessWidget {
  final TextEditingController controller;
  final void Function(String) onSubmit;

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
              onSubmitted: onSubmit,
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
