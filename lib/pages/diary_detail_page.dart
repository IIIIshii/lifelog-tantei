import 'package:flutter/material.dart';

class DiaryDetailPage extends StatelessWidget {
  final String date;
  final String diary;

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
