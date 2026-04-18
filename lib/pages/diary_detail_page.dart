import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/detective_text_styles.dart';
import '../services/firestore_service.dart';
import 'diary_edit_page.dart';

// 特定の日の日記を事件報告書として全文表示する詳細ページ
class DiaryDetailPage extends StatelessWidget {
  final String date;               // 表示する日付（YYYY-MM-DD）
  final String diary;              // 表示する日記テキスト
  final String uid;                // 編集保存に必要なユーザーID
  final FirestoreService firestore;

  const DiaryDetailPage({
    super.key,
    required this.date,
    required this.diary,
    required this.uid,
    required this.firestore,
  });

  // YYYY-MM-DD → YYYY年MM月DD日 に整形する（diary_list_pageと同じ形式）
  String _formatDate(String raw) {
    final parts = raw.split('-');
    if (parts.length != 3) return raw;
    return '${parts[0]}年${parts[1]}月${parts[2]}日';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,

      // ── AppBar ──────────────────────────────────────────────
      // 日付を整形して表示し、サブタイトルで「事件報告書」であることを示す
      appBar: AppBar(
        backgroundColor: c.appBarBg,
        foregroundColor: c.appBarFg,
        elevation: 0,
        toolbarHeight: 64,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_formatDate(date),
                style: DetectiveTextStyles.appBarTitle(color: c.appBarFg)),
            const SizedBox(height: 2),
            Text('― 事件報告書 ―',
                style: DetectiveTextStyles.appBarSubtitle(
                    color: c.appBarSubtitle)),
          ],
        ),
      ),

      // ── Body ────────────────────────────────────────────────
      body: Column(
        children: [
          Expanded(child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Container(
          decoration: BoxDecoration(
            color: c.cardBg,
            borderRadius: BorderRadius.circular(4),
            // ゴールドの枠線でDiaryCardと同じ「重要書類」感を表現する
            border: Border.all(color: c.gold, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── ヘッダー行（DiaryCardと同じデザイン） ────────
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: c.gold)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.description, color: c.gold, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      '事件報告書',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: c.gold,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const Spacer(),
                    // CLOSEDバッジ
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        border: Border.all(color: c.gold),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Text(
                        'CLOSED',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: c.gold,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── 日記本文（全文表示） ──────────────────────────
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  diary,
                  style: TextStyle(
                    fontSize: 16,
                    color: c.textPrimary,
                    height: 1.8, // 行間を広めにとって読みやすくする
                  ),
                ),
              ),
            ],
          ),
          ))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DiaryEditPage(
                      uid: uid,
                      today: date,
                      firestore: firestore,
                      initialDiary: diary,
                    ),
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.gold,
                  foregroundColor: c.appBarFg,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4)),
                ),
                child: const Text('編集する',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
