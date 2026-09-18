import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

// 設定系の画面で共通して使う、書類風セクションの部品をまとめたファイル。
// もともと settings_page.dart のプライベートウィジェットだったものを、
// 自己分析ページ（self_analysis_page.dart）と見た目を揃えるために切り出した。
// 見た目・挙動は移設前のまま変えていない。
//
// 見出しに付ける「◆ 」は呼び出し側が title に含める（セクションごとに付けない選択もできるため）。

// ──────────────────────────────────────────────────────────────
// セクションの見出しウィジェット
//
// タイトル（太字・ゴールド）とその下に機能説明のサブタイトルを表示する。
// ◆ 記号でノワール感のある区切りを演出する。
// ──────────────────────────────────────────────────────────────
class SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const SectionHeader({super.key, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: c.gold,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(subtitle, style: TextStyle(fontSize: 11, color: c.textSecondary)),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────
// 設定項目をまとめる書類風カードウィジェット
//
// ホームのカードと同じテイストでクリーム背景＋ゴールド枠線を使用。
// 角丸を小さくして書類感を強調する。
// 子同士の区切り線は呼び出し側で Divider を挟む。
// ──────────────────────────────────────────────────────────────
class SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const SettingsCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.cardBorder),
      ),
      // ClipRRectでカード内のウィジェットが角丸からはみ出ないようにする
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Column(children: children),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// 各設定項目のスイッチ付きタイルウィジェット
//
// onChangedがnullの場合はスイッチが無効（変更不可）になる。
// 必須項目（イベント記録）や、前提が未設定の項目はnullを渡してグレーアウトする。
// ──────────────────────────────────────────────────────────────
class SettingsSwitchTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged; // nullの場合はスイッチが無効（変更不可）

  const SettingsSwitchTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SwitchListTile(
      title: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: c.textPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: c.textSecondary),
      ),
      value: value,
      onChanged: onChanged,
      // アクティブ時はゴールドで探偵テーマに統一（activeColorはv3.31以降非推奨）
      activeThumbColor: c.onAccent,
      activeTrackColor: c.gold,
    );
  }
}
