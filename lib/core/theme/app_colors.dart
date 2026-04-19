import 'package:flutter/material.dart';

/// アプリ固有の色トークンを ThemeData に差し込むための ThemeExtension。
///
/// なぜ ThemeExtension を使うのか：
/// Flutter 標準の ColorScheme（primary/secondary/surface 等）には
/// 探偵テーマ固有の gold / cardBorder / bubble といった概念がそのままでは収まらない。
/// かといって独自クラスを InheritedWidget で自前配信すると、
/// Flutter 公式の themeMode/Theme.of() の流儀から外れてしまう。
/// ThemeExtension なら「標準の ThemeData に型安全な拡張を差し込める」ため、
/// 標準機構を壊さずにドメイン固有の色を運べる。
class AppColors extends ThemeExtension<AppColors> {
  final Color background; // 画面全体の背景
  final Color appBarBg; // AppBar の背景
  final Color appBarFg; // AppBar のタイトル・アイコン色
  final Color appBarSubtitle; // AppBar のサブタイトル（イタリック）色
  final Color cardBg; // カード背景
  final Color cardBorder; // カード外枠線
  final Color gold; // アクセント（濃いめ）
  final Color goldLight; // アクセント（薄め・タブ背景など）
  final Color textPrimary; // 主要テキスト
  final Color textSecondary; // 補助テキスト
  final Color bubbleUser; // 会話：ユーザーの吹き出し背景
  final Color bubbleAi; // 会話：AIの吹き出し背景
  final Color caseNumberFg; // フォルダータブのケース番号色（背景はgoldLight想定）

  const AppColors({
    required this.background,
    required this.appBarBg,
    required this.appBarFg,
    required this.appBarSubtitle,
    required this.cardBg,
    required this.cardBorder,
    required this.gold,
    required this.goldLight,
    required this.textPrimary,
    required this.textSecondary,
    required this.bubbleUser,
    required this.bubbleAi,
    required this.caseNumberFg,
  });

  @override
  AppColors copyWith({
    Color? background,
    Color? appBarBg,
    Color? appBarFg,
    Color? appBarSubtitle,
    Color? cardBg,
    Color? cardBorder,
    Color? gold,
    Color? goldLight,
    Color? textPrimary,
    Color? textSecondary,
    Color? bubbleUser,
    Color? bubbleAi,
    Color? caseNumberFg,
  }) {
    return AppColors(
      background: background ?? this.background,
      appBarBg: appBarBg ?? this.appBarBg,
      appBarFg: appBarFg ?? this.appBarFg,
      appBarSubtitle: appBarSubtitle ?? this.appBarSubtitle,
      cardBg: cardBg ?? this.cardBg,
      cardBorder: cardBorder ?? this.cardBorder,
      gold: gold ?? this.gold,
      goldLight: goldLight ?? this.goldLight,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      bubbleUser: bubbleUser ?? this.bubbleUser,
      bubbleAi: bubbleAi ?? this.bubbleAi,
      caseNumberFg: caseNumberFg ?? this.caseNumberFg,
    );
  }

  /// テーマ切替アニメーション時の補間（ThemeExtension の契約で必須）。
  /// Color.lerp は t=0 で this、t=1 で other を返す。
  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      appBarBg: Color.lerp(appBarBg, other.appBarBg, t)!,
      appBarFg: Color.lerp(appBarFg, other.appBarFg, t)!,
      appBarSubtitle: Color.lerp(appBarSubtitle, other.appBarSubtitle, t)!,
      cardBg: Color.lerp(cardBg, other.cardBg, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      gold: Color.lerp(gold, other.gold, t)!,
      goldLight: Color.lerp(goldLight, other.goldLight, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      bubbleUser: Color.lerp(bubbleUser, other.bubbleUser, t)!,
      bubbleAi: Color.lerp(bubbleAi, other.bubbleAi, t)!,
      caseNumberFg: Color.lerp(caseNumberFg, other.caseNumberFg, t)!,
    );
  }
}

/// BuildContext から `context.colors.gold` のように短く書けるようにする拡張メソッド。
///
/// なぜ extension を作るか：
/// 毎回 `Theme.of(context).extension<AppColors>()!` と書くと冗長かつ
/// null チェックの `!` が散らかる。拡張で1行にまとめることで可読性を確保しつつ、
/// 万一の null（テーマ未設定）は起動時の初期化ミスとして早期に顕在化させる。
extension BuildContextColors on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
