import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 探偵テーマ全体で共通のテキストスタイル（フォント・サイズ・weight 等）。
///
/// なぜ色と分離するか：
/// フォント選定（Playfair Display など）はテーマが変わっても基本的に共通で保ちたい
/// （探偵アプリの世界観の軸）。一方で色はテーマごとに切り替わる。
/// この2つをまとめてしまうとテーマごとに全く同じフォント指定を重複させる羽目になる。
/// そのため「形（フォント・サイズ）」は静的定数、「色」は使用側で AppColors から指定する運用にする。
class DetectiveTextStyles {
  DetectiveTextStyles._();

  /// AppBarタイトル：クラシック探偵小説風の Playfair Display。
  /// 色は使用側で withColor 相当として copyWith(color: ...) で上書きする想定。
  static TextStyle appBarTitle({Color? color}) =>
      GoogleFonts.playfairDisplay(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: color,
        letterSpacing: 1.5,
      );

  /// AppBarサブタイトル：イタリック体でキャッチコピー用。
  static TextStyle appBarSubtitle({Color? color}) => TextStyle(
        fontSize: 11,
        color: color,
        letterSpacing: 2.0,
        fontStyle: FontStyle.italic,
      );

  /// フォルダータブのケース番号（No.01 など）。
  static TextStyle caseNumber({Color? color}) => GoogleFonts.playfairDisplay(
        fontSize: 10,
        fontWeight: FontWeight.bold,
        color: color,
        letterSpacing: 1.0,
      );

  /// カードタイトル。
  static TextStyle cardTitle({Color? color}) => TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: color,
      );

  /// カードサブタイトル（日本語説明の括弧書き）。
  static TextStyle cardSubtitle({Color? color}) => TextStyle(
        fontSize: 12,
        color: color,
      );

  /// ホーム画面のキャッチコピー。
  static TextStyle catchphrase({Color? color}) => TextStyle(
        fontSize: 13,
        color: color,
        fontStyle: FontStyle.italic,
        letterSpacing: 0.5,
      );
}
