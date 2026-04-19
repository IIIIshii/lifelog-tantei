import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/detective_text_styles.dart';
import '../services/auth_service.dart';
import 'diary_page.dart';
import 'analytics_page.dart';
import 'diary_list_page.dart';
import 'settings_page.dart';

// アプリのホーム画面。4つのメニューカードを表示する
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _uid;
  final AuthService _auth = AuthService();

  @override
  void initState() {
    super.initState();
    _initUid();
  }

  // 匿名サインインしてUIDを取得する。UID取得前はメニューボタンを無効化する
  Future<void> _initUid() async {
    final uid = await _auth.signInAnonymously();
    setState(() => _uid = uid);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,

      // ── AppBar ──────────────────────────────────────────────
      // タイトルにサブタイトルを重ねることで探偵事務所の看板風に見せる
      appBar: AppBar(
        backgroundColor: c.appBarBg,
        elevation: 0,
        toolbarHeight: 64,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ライフログ探偵',
                style: DetectiveTextStyles.appBarTitle(color: c.appBarFg)),
            const SizedBox(height: 2),
            Text('― 事件、受け付けます ―',
                style: DetectiveTextStyles.appBarSubtitle(
                    color: c.appBarSubtitle)),
          ],
        ),
      ),

      // ── Body ────────────────────────────────────────────────
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // キャッチコピー
            Text(
              '今日も新たな記録が待っている——',
              style: DetectiveTextStyles.catchphrase(color: c.textSecondary),
            ),
            const SizedBox(height: 28),

            // ── メニューカード一覧 ──────────────────────────
            // 各カードはマニラフォルダー風のデザインで「事件ファイル」を表現
            _CaseFileCard(
              caseNumber: 'No.01',
              icon: Icons.search,
              title: '新規事件を開く',
              subtitle: '（日記をつける）',
              onTap: _uid == null
                  ? null
                  : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const DiaryPage()),
                      ),
            ),
            const SizedBox(height: 16),
            _CaseFileCard(
              caseNumber: 'No.02',
              icon: Icons.folder_open,
              title: '事件簿アーカイブ',
              subtitle: '（過去の日記を見る）',
              onTap: _uid == null
                  ? null
                  : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => DiaryListPage(uid: _uid!)),
                      ),
            ),
            const SizedBox(height: 16),
            _CaseFileCard(
              caseNumber: 'No.03',
              icon: Icons.analytics,
              title: '証拠分析室',
              subtitle: '（習慣や行動をグラフで見る）',
              onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AnalyticsPage()),
                  ),
            ),
            const SizedBox(height: 16),
            _CaseFileCard(
              caseNumber: 'No.04',
              icon: Icons.business_center,
              title: '探偵事務所',
              subtitle: '（設定する）',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              ),
            ),
          ],
        ),
      ),
    );
  }

}

// ──────────────────────────────────────────────────────────────
// マニラフォルダー風カード
//
// 上部にケース番号のタブを付け、左端にゴールドの縦ボーダーを引くことで
// 「事件ファイル」らしい書類感を演出する。
// ──────────────────────────────────────────────────────────────
class _CaseFileCard extends StatelessWidget {
  final String caseNumber;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _CaseFileCard({
    required this.caseNumber,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // タブ部分の高さ（フォルダータブを再現する）
    const double tabHeight = 22.0;
    final c = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── フォルダータブ（ケース番号） ──────────────────────
        // カード左上に突き出す小さなタブでマニラフォルダーを表現
        Container(
          height: tabHeight,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: c.goldLight,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(8),
            ),
          ),
          alignment: Alignment.center,
          child: Text(caseNumber,
              style: DetectiveTextStyles.caseNumber(color: c.caseNumberFg)),
        ),

        // ── メインカード本体 ──────────────────────────────────
        // タブの直下に配置し、左上の角だけ角丸なしにしてタブとの接続を自然に見せる
        Material(
          color: c.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(4),
              bottomLeft: Radius.circular(4),
              bottomRight: Radius.circular(4),
            ),
            side: BorderSide(color: c.cardBorder),
          ),
          child: InkWell(
            onTap: onTap,
            customBorder: const RoundedRectangleBorder(
              borderRadius: BorderRadius.only(
                topRight: Radius.circular(4),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(4),
              ),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 左端のゴールドアクセントボーダー
                  Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: c.gold,
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(4),
                      ),
                    ),
                  ),

                  // カード本文
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          // アイコン
                          Icon(icon, color: c.gold, size: 28),
                          const SizedBox(width: 16),

                          // タイトル + サブタイトル
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title,
                                  style: DetectiveTextStyles.cardTitle(
                                      color: c.textPrimary)),
                              const SizedBox(height: 2),
                              Text(subtitle,
                                  style: DetectiveTextStyles.cardSubtitle(
                                      color: c.textSecondary)),
                            ],
                          ),

                          const Spacer(),

                          // 右端の矢印
                          Icon(Icons.chevron_right, color: c.goldLight),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
