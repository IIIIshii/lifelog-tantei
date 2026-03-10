import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_service.dart';
import 'diary_detail_page.dart';

class DiaryListPage extends StatelessWidget {
  final String uid;

  const DiaryListPage({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    final entriesRef = FirestoreService().entriesQuery(uid);

    return Scaffold(
      appBar: AppBar(title: const Text('過去の日記')),
      body: StreamBuilder<QuerySnapshot>(
        stream: entriesRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('エラー: ${snapshot.error}'));
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('まだ日記がありません'));
          }
          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final date = docs[index].id;
              final diary = data['diary'] as String? ?? '';
              return ListTile(
                leading: const Icon(Icons.book),
                title: Text(date),
                subtitle: Text(
                  diary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          DiaryDetailPage(date: date, diary: diary),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
