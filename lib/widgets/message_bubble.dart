import 'package:flutter/material.dart';

class MessageBubble extends StatelessWidget {
  final String role;
  final String text;

  const MessageBubble({super.key, required this.role, required this.text});

  @override
  Widget build(BuildContext context) {
    final isAI = role == 'ai';
    return Align(
      alignment: isAI ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: isAI ? Colors.grey[200] : Colors.blue[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(text),
      ),
    );
  }
}
