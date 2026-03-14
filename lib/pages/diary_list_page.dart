import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/theme/detective_theme.dart';
import '../services/firestore_service.dart';
import 'diary_detail_page.dart';

// 過去の日記一覧を事件簿アーカイブとして表示するページ
class DiaryListPage extends StatelessWidget {
  final String uid;

  const DiaryListPage({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    final entriesRef = FirestoreService().entriesQuery(uid);

    return Scaffold(
      backgroundColor: DetectiveTheme.background,

      // ── AppBar ──────────────────────────────────────────────
      appBar: AppBar(
        backgroundColor: DetectiveTheme.appBarBg,
        foregroundColor: const Color(0xFFE8DCC8),
        elevation: 0,
        toolbarHeight: 64,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('事件簿アーカイブ', style: DetectiveTheme.appBarTitle),
            const SizedBox(height: 2),
            const Text('― 過去の記録を参照する ―',
                style: DetectiveTheme.appBarSubtitle),
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
            return const Center(
              child: CircularProgressIndicator(color: DetectiveTheme.gold),
            );
          }

          if (snapshot.hasError) {
            return Center(child: Text('エラー: ${snapshot.error}'));
          }
          // diary フィールドがないドキュメント（会話途中で終わったもの等）を除外する
          final docs = (snapshot.data?.docs ?? [])
              .where((d) => (d.data() as Map<String, dynamic>)['diary'] != null)
              .toList();
          if (docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder_open,
                      size: 48, color: DetectiveTheme.cardBorder),
                  SizedBox(height: 12),
                  Text(
                    'まだ事件の記録がありません',
                    style: TextStyle(
                      color: DetectiveTheme.textSecondary,
                      fontSize: 14,
                    ),
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
              return _CaseArchiveItem(
                date: date,
                diary: diary,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        DiaryDetailPage(date: date, diary: diary),
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

// ──────────────────────────────────────────────────────────────
// 事件簿アーカイブの1件分の表示ウィジェット
//
// ホームのCaseFileCardと同じファイル風デザインを踏襲し、
// 左端ゴールドボーダー＋日付ゴールド表示で統一感を持たせる。
// ──────────────────────────────────────────────────────────────
class _CaseArchiveItem extends StatelessWidget {
  final String date;   // YYYY-MM-DD形式
  final String diary;  // 日記本文（プレビュー用）
  final VoidCallback onTap;

  const _CaseArchiveItem({
    required this.date,
    required this.diary,
    required this.onTap,
  });

  // YYYY-MM-DD → YYYY年MM月DD日 に整形する
  String _formatDate(String raw) {
    final parts = raw.split('-');
    if (parts.length != 3) return raw;
    return '${parts[0]}年${parts[1]}月${parts[2]}日';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DetectiveTheme.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(4)),
        side: BorderSide(color: DetectiveTheme.cardBorder),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 左端のゴールドアクセントボーダー（ホームカードと同スタイル）
              Container(
                width: 4,
                decoration: const BoxDecoration(
                  color: DetectiveTheme.gold,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(4),
                    bottomLeft: Radius.circular(4),
                  ),
                ),
              ),

              // 日付と日記プレビュー
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 日付（ゴールド太字でアーカイブ番号のように見せる）
                      Row(
                        children: [
                          const Icon(Icons.folder_open,
                              size: 14, color: DetectiveTheme.gold),
                          const SizedBox(width: 6),
                          Text(
                            _formatDate(date),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: DetectiveTheme.gold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // 日記本文のプレビュー（2行まで）
                      Text(
                        diary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: DetectiveTheme.textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 右端の矢印アイコン
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Icon(Icons.chevron_right,
                    color: DetectiveTheme.goldLight, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
