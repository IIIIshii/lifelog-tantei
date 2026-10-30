import 'package:flutter/material.dart';
import '../core/ai_data_disclosure.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/detective_text_styles.dart';
import '../widgets/settings_section.dart';

// 入力した内容が AI（Gemini）に送られることと、何が送られるかを示す画面。
// 設定の「AIへの送信について」から push で開く。
//
// 保存や通信はしない読み物なので StatelessWidget にしている。
// 一覧の中身は core/ai_data_disclosure.dart に置いてある。
class AiDataNoticePage extends StatelessWidget {
  const AiDataNoticePage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
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
              'AIへの送信について',
              style: DetectiveTextStyles.appBarTitle(color: c.appBarFg),
            ),
            const SizedBox(height: 2),
            Text(
              '― 入力した内容が渡る範囲 ―',
              style: DetectiveTextStyles.appBarSubtitle(
                color: c.appBarSubtitle,
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            '入力した内容は、質問・日記・所見を作るために、'
            '$aiProviderNameへ送られます。',
            style: TextStyle(fontSize: 14, height: 1.6, color: c.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            '送った先での取り扱いは、提供元の規約に従います。',
            style: TextStyle(fontSize: 12, height: 1.6, color: c.textSecondary),
          ),
          const SizedBox(height: 24),
          const SectionHeader(title: '◆ 送られる内容', subtitle: '使う機能によって、必要なものだけが渡ります'),
          const SizedBox(height: 8),
          SettingsCard(
            children: [
              for (var i = 0; i < aiDataItems.length; i++) ...[
                _AiDataTile(item: aiDataItems[i]),
                if (i < aiDataItems.length - 1)
                  Divider(height: 1, color: c.cardBorder),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// 一覧の1項目。何が・どんな内容で・何に使われるか・条件、の順に並べる。
class _AiDataTile extends StatelessWidget {
  final AiDataItem item;

  const _AiDataTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final small = TextStyle(fontSize: 12, height: 1.5, color: c.textSecondary);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(item.detail, style: small),
          Text('使い道: ${item.usedFor}', style: small),
          if (item.note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                item.note,
                style: small.copyWith(color: c.gold),
              ),
            ),
        ],
      ),
    );
  }
}
