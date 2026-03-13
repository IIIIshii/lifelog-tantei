import 'package:flutter/material.dart';

// 生成された日記を会話リストの末尾に表示するカードウィジェット
class DiaryCard extends StatelessWidget {
  final String diary; // 表示する日記テキスト

  const DiaryCard({super.key, required this.diary});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 12),
      color: Colors.amber[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('今日の日記',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Text(diary),
          ],
        ),
      ),
    );
  }
}
