import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/detective_text_styles.dart';
import '../services/firestore_service.dart';
import '../widgets/case_archive_tile.dart';
import 'diary_detail_page.dart';

// 過去の日記一覧を事件簿アーカイブとして表示するページ
class DiaryListPage extends StatelessWidget {
  final String uid;

  const DiaryListPage({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    final entriesRef = FirestoreService().entriesQuery(uid);
    final c = context.colors;

    return Scaffold(
      backgroundColor: c.background,

      // ── AppBar ──────────────────────────────────────────────
      appBar: AppBar(
        backgroundColor: c.appBarBg,
        foregroundColor: c.appBarFg,
        elevation: 0,
        toolbarHeight: 64,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '事件簿アーカイブ',
              style: DetectiveTextStyles.appBarTitle(color: c.appBarFg),
            ),
            const SizedBox(height: 2),
            Text(
              '― 過去の記録を参照する ―',
              style: DetectiveTextStyles.appBarSubtitle(
                color: c.appBarSubtitle,
              ),
            ),
          ],
        ),
      ),

      // ── Body ────────────────────────────────────────────────
      // Firestoreのリアルタイム更新をStreamBuilderで受け取って一覧を描画する
      body: StreamBuilder<QuerySnapshot>(
        stream: entriesRef.snapshots(),
        builder: (context, snapshot) {
          // 読み込み中: ゴールドのローディングインジケーター
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: c.gold));
          }

          if (snapshot.hasError) {
            return Center(child: Text('エラー: ${snapshot.error}'));
          }
          // diary フィールドがないドキュメント（会話途中で終わったもの等）を除外し、
          // ドキュメントID（YYYY-MM-DD）の降順（新しい順）でクライアントソートする
          final docs =
              (snapshot.data?.docs ?? [])
                  .where(
                    (d) => (d.data() as Map<String, dynamic>)['diary'] != null,
                  )
                  .toList()
                ..sort((a, b) => b.id.compareTo(a.id));
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder_open, size: 48, color: c.cardBorder),
                  const SizedBox(height: 12),
                  Text(
                    'まだ事件の記録がありません',
                    style: TextStyle(color: c.textSecondary, fontSize: 14),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            // 区切り線はゴールド系のカードボーダー色で統一する
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final date = docs[index].id; // ドキュメントIDが日付（YYYY-MM-DD）
              final diary = data['diary'] as String;

              // タップで日記詳細ページへ遷移する
              final firestore = FirestoreService();
              return CaseArchiveTile(
                date: date,
                diary: diary,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DiaryDetailPage(
                      date: date,
                      diary: diary,
                      uid: uid,
                      firestore: firestore,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
