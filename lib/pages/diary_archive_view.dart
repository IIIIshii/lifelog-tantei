import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../models/archive_month.dart';
import '../services/firestore_service.dart';
import '../widgets/archive_book.dart';
import 'diary_detail_page.dart';
import 'diary_month_page.dart';

// 本1冊の高さ。幅は画面幅から決まるが、中身（アイコン・年・月・件数）の縦の積み上げは
// 幅に関係なく一定なので、高さは固定値にする。
const _bookHeight = 186.0;

// 過去の日記を月ごとの本棚として並べる事件簿アーカイブ。
// 本をタップすると、その月のカレンダーとプレビュー（DiaryMonthPage）へ進む。
//
// 事件簿タブ（CaseFilesPage）の「アーカイブ」側の中身。AppBar はタブ側が持つので、
// ここは本文だけを返す。
//
// StatefulWidget なのは購読を1本に保つため。build のたびに Stream を作ると、
// タブの切り替えなどで再描画されるたびに購読し直してスピナーが挟まる。
class DiaryArchiveView extends StatefulWidget {
  final String uid;

  const DiaryArchiveView({super.key, required this.uid});

  @override
  State<DiaryArchiveView> createState() => _DiaryArchiveViewState();
}

class _DiaryArchiveViewState extends State<DiaryArchiveView>
    with AutomaticKeepAliveClientMixin {
  late final Stream<Map<String, String>> _stream = FirestoreService()
      .diaryTextsStream(widget.uid);

  // タブを横に切り替えても本棚を作り直さない
  @override
  bool get wantKeepAlive => true;

  void _openMonth(BuildContext context, ArchiveMonth month) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => DiaryMonthPage(
          year: month.year,
          month: month.month,
          // 月ページへは新しく購読を作って渡す。Stream を共有すると、後から購読した側に
          // 初回のデータが届かず、次の更新までスピナーのままになるため。
          entries: FirestoreService().diaryTextsStream(widget.uid),
          onOpenDetail: (date, diary) => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => DiaryDetailPage(
                date: date,
                diary: diary,
                uid: widget.uid,
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
    super.build(context);
    final c = context.colors;

    // Firestoreのリアルタイム更新をStreamBuilderで受け取って本棚を描画する
    return StreamBuilder<Map<String, String>>(
      stream: _stream,
      builder: (context, snapshot) {
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
    );
  }
}
