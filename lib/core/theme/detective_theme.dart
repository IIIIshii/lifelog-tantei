import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 探偵テーマの色・テキストスタイル定数
///
/// ノワール・レトロ調のライトブラウン系パレット。
/// アプリ全体のデザイントークンをここに集約することで、
/// 色やフォントの変更を一箇所で管理できる。
class DetectiveTheme {
  DetectiveTheme._(); // インスタンス化禁止

  // ── カラーパレット ──────────────────────────────────────────

  /// 背景：古い羊皮紙のようなライトブラウン
  static const Color background = Color(0xFFF0E6D3);

  /// AppBar・ヘッダー：濃いインク色
  static const Color appBarBg = Color(0xFF2C1A0E);

  /// カード背景：薄いクリーム
  static const Color cardBg = Color(0xFFFBF5EC);

  /// アクセント：くすみゴールド（枠線・アイコン・強調テキスト）
  static const Color gold = Color(0xFF8B6914);

  /// アクセント薄め：カードタブ背景など
  static const Color goldLight = Color(0xFFC9A84C);

  /// メインテキスト：インク黒
  static const Color textPrimary = Color(0xFF1A0F05);

  /// サブテキスト：茶インク
  static const Color textSecondary = Color(0xFF6B4C2A);

  /// カード外枠線：薄いベージュ
  static const Color cardBorder = Color(0xFFD4B896);

  // ── テキストスタイル ────────────────────────────────────────

  /// AppBarタイトル：Playfair Display でクラシック探偵小説風に
  static TextStyle get appBarTitle => GoogleFonts.playfairDisplay(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: const Color(0xFFE8DCC8),
        letterSpacing: 1.5,
      );

  /// AppBarサブタイトル：イタリック体でキャッチコピーを表示
  static const TextStyle appBarSubtitle = TextStyle(
    fontSize: 11,
    color: Color(0xFFB89A6A),
    letterSpacing: 2.0,
    fontStyle: FontStyle.italic,
  );

  /// フォルダータブのケース番号（No.01 など）
  static TextStyle get caseNumber => GoogleFonts.playfairDisplay(
        fontSize: 10,
        fontWeight: FontWeight.bold,
        color: const Color(0xFF2C1A0E),
        letterSpacing: 1.0,
      );

  /// カードタイトル（探偵風の事件名）
  static const TextStyle cardTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.bold,
    color: textPrimary,
  );

  /// カードサブタイトル（日本語説明の括弧書き）
  static const TextStyle cardSubtitle = TextStyle(
    fontSize: 12,
    color: textSecondary,
  );

  /// ホーム画面のキャッチコピー
  static const TextStyle catchphrase = TextStyle(
    fontSize: 13,
    color: textSecondary,
    fontStyle: FontStyle.italic,
    letterSpacing: 0.5,
  );
}
