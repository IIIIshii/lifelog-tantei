import 'package:flutter/material.dart';

// 特定の日の日記を全文表示する詳細ページ
class DiaryDetailPage extends StatelessWidget {
  final String date; // 表示する日付（YYYY-MM-DD）
  final String diary; // 表示する日記テキスト

  const DiaryDetailPage({super.key, required this.date, required this.diary});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(date)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Card(
          color: Colors.amber[50],
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(diary,
                style: const TextStyle(fontSize: 16, height: 1.8)),
          ),
        ),
      ),
    );
  }
}
