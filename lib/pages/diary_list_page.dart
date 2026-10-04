import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/detective_text_styles.dart';
import '../models/archive_month.dart';
import '../services/firestore_service.dart';
import '../widgets/archive_book.dart';
import 'diary_detail_page.dart';
import 'diary_month_page.dart';

// 本1冊の高さ。幅は画面幅から決まるが、中身（アイコン・年・月・件数）の縦の積み上げは
// 幅に関係なく一定なので、高さは固定値にする。
const _bookHeight = 186.0;

// 過去の日記を月ごとの本棚として並べる事件簿アーカイブ
// 本をタップすると、その月のカレンダーとプレビュー（DiaryMonthPage）へ進む
class DiaryListPage extends StatelessWidget {
  final String uid;

  const DiaryListPage({super.key, required this.uid});

  // 日付（YYYY-MM-DD）→日記本文のストリーム。
  // diary フィールドがないドキュメント（会話途中で終わったもの等）は除外する。
  // 月ページへも同じ関数で新しく購読を作って渡す。Stream を共有すると、後から購読した側に
  // 初回のデータが届かず、次の更新までスピナーのままになるため。
  Stream<Map<String, String>> _entriesStream() {
    return FirestoreService()
        .entriesQuery(uid)
        .snapshots()
        .map(
          (snapshot) => {
            for (final doc in snapshot.docs)
              if (doc.data()['diary'] != null)
                doc.id: doc.data()['diary'] as String,
          },
        );
  }

  void _openMonth(BuildContext context, ArchiveMonth month) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DiaryMonthPage(
          year: month.year,
          month: month.month,
          entries: _entriesStream(),
          // タップで日記詳細ページへ遷移する
          onOpenDetail: (date, diary) => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DiaryDetailPage(
                date: date,
                diary: diary,
                uid: uid,
                firestore: FirestoreService(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              '― 月ごとの事件簿を開く ―',
              style: DetectiveTextStyles.appBarSubtitle(
                color: c.appBarSubtitle,
              ),
            ),
          ],
        ),
      ),

      // ── Body ────────────────────────────────────────────────
      // Firestoreのリアルタイム更新をStreamBuilderで受け取って本棚を描画する
      body: StreamBuilder<Map<String, String>>(
        stream: _entriesStream(),
        builder: (context, snapshot) {
          // 読み込み中: ゴールドのローディングインジケーター
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: c.gold));
          }

          if (snapshot.hasError) {
            return Center(child: Text('エラー: ${snapshot.error}'));
          }

          // 日付キーが不正なドキュメントがあれば、黙って捨てずにエラーとして見せる
          final List<ArchiveMonth> months;
          try {
            months = groupByMonth(snapshot.data ?? const {});
          } on FormatException catch (e) {
            return Center(child: Text('エラー: ${e.message}（${e.source}）'));
          }

          if (months.isEmpty) {
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

          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              mainAxisExtent: _bookHeight,
            ),
            itemCount: months.length,
            itemBuilder: (context, index) {
              final month = months[index];
              return ArchiveBook(
                month: month,
                onTap: () => _openMonth(context, month),
              );
            },
          );
        },
      ),
    );
  }
}
