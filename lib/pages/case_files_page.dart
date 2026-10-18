import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/detective_text_styles.dart';
import 'analytics_view.dart';
import 'diary_archive_view.dart';

// 事件簿タブ（記録確認）。過去の日記を読み返す「アーカイブ」と、
// 日々の記録を可視化して AI に読ませる「分析」を、上部のタブで切り替える。
//
// 以前はボトムナビに事件簿と分析室が別々に並んでいた。どちらも「記録を読み返す」
// 行き先なので1つにまとめ、空いた枠の分ボトムナビを4つに減らした
// （主要動線の「今日の捜査」は FAB が担うので、行き先にする必要が無い）。
class CaseFilesPage extends StatelessWidget {
  final String uid;

  /// 分析を読み直すシグナル（MainShell がこのタブを開くたびに進める）
  final ValueListenable<int> refreshSignal;

  const CaseFilesPage({
    super.key,
    required this.uid,
    required this.refreshSignal,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(
          backgroundColor: c.appBarBg,
          foregroundColor: c.appBarFg,
          elevation: 0,
          toolbarHeight: 64,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '事件簿',
                style: DetectiveTextStyles.appBarTitle(color: c.appBarFg),
              ),
              const SizedBox(height: 2),
              Text(
                '― 記録を読み返す ―',
                style: DetectiveTextStyles.appBarSubtitle(
                  color: c.appBarSubtitle,
                ),
              ),
            ],
          ),
          // バー（appBarBg）の上に乗るので、文字は appBarFg / appBarSubtitle、
          // 選択中の下線は「暗い面の上に敷く明るい面」の goldLight を使う
          bottom: TabBar(
            labelColor: c.appBarFg,
            unselectedLabelColor: c.appBarSubtitle,
            indicatorColor: c.goldLight,
            indicatorWeight: 3,
            dividerColor: Colors.transparent,
            labelStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
            unselectedLabelStyle: const TextStyle(fontSize: 13),
            tabs: const [
              Tab(icon: Icon(Icons.menu_book_outlined, size: 18), text: 'アーカイブ'),
              Tab(icon: Icon(Icons.insights_outlined, size: 18), text: '分析'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            DiaryArchiveView(uid: uid),
            AnalyticsView(uid: uid, refreshSignal: refreshSignal),
          ],
        ),
      ),
    );
  }
}
