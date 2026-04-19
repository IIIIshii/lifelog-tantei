import 'package:flutter/material.dart';
import 'app_colors.dart';

/// 選択可能なテーマの列挙。
/// SharedPreferences に保存する際は .name を key として使う。
enum AppThemeName {
  detectiveLight, // 探偵（ライト・セピア）
  detectiveDark, // ダーク（ノワール）
  study, // 書斎（ブリティッシュグリーン + ブラス）
}

/// 日本語表示名（設定画面のラジオボタン表示用）。
extension AppThemeNameLabel on AppThemeName {
  String get label {
    switch (this) {
      case AppThemeName.detectiveLight:
        return '探偵（ライト）';
      case AppThemeName.detectiveDark:
        return '探偵（ダーク / ノワール）';
      case AppThemeName.study:
        return '書斎';
    }
  }

  String get description {
    switch (this) {
      case AppThemeName.detectiveLight:
        return '羊皮紙のような温かみのあるセピア調';
      case AppThemeName.detectiveDark:
        return '深夜の探偵事務所。インク色の闇とゴールド';
      case AppThemeName.study:
        return 'ロンドンの古書斎。緑と真鍮の落ち着いた雰囲気';
    }
  }
}

/// ── カラーパレット定義 ──────────────────────────────────────
/// 各テーマは AppColors インスタンスとして定義し、buildTheme() で ThemeData に焼き付ける。

// ライト（現行の探偵セピア）
// bubbleAi = カード色と同じクリーム / bubbleUser = それより一段濃いタン
// テキストは双方 textPrimary（黒系）で可読性を確保
const _lightColors = AppColors(
  background: Color(0xFFF0E6D3), // 古い羊皮紙
  appBarBg: Color(0xFF2C1A0E), // 濃いインク
  appBarFg: Color(0xFFE8DCC8),
  appBarSubtitle: Color(0xFFB89A6A),
  cardBg: Color(0xFFFBF5EC), // クリーム
  cardBorder: Color(0xFFD4B896),
  gold: Color(0xFF8B6914),
  goldLight: Color(0xFFC9A84C),
  textPrimary: Color(0xFF1A0F05),
  textSecondary: Color(0xFF6B4C2A),
  bubbleUser: Color(0xFFE8DDD0), // 一段濃いタン（元の実装を踏襲）
  bubbleAi: Color(0xFFFBF5EC),
  caseNumberFg: Color(0xFF2C1A0E),
);

// ダーク（ノワール）
// bubbleAi = カード色と同じ焦茶 / bubbleUser = ひとつ明るいブラウン
// テキストは双方 textPrimary（クリーム）
const _darkColors = AppColors(
  background: Color(0xFF1A0F05), // 深いインク
  appBarBg: Color(0xFF0D0604), // 漆黒
  appBarFg: Color(0xFFE8DCC8),
  appBarSubtitle: Color(0xFFB89A6A),
  cardBg: Color(0xFF2C1A0E), // 焦茶
  cardBorder: Color(0xFF5C3D2E),
  gold: Color(0xFFC9A84C), // ダーク時は明るい金にしてコントラスト確保
  goldLight: Color(0xFF8B6914),
  textPrimary: Color(0xFFE8DCC8), // クリーム
  textSecondary: Color(0xFFB89A6A),
  bubbleUser: Color(0xFF5C3D2E), // ひとつ明るいブラウン
  bubbleAi: Color(0xFF2C1A0E),
  caseNumberFg: Color(0xFF1A0F05),
);

// 書斎（ブリティッシュグリーン + ブラス）
const _studyColors = AppColors(
  background: Color(0xFFE8DFC5), // 古紙
  appBarBg: Color(0xFF1F3A2E), // ブリティッシュグリーン
  appBarFg: Color(0xFFE8DFC5),
  appBarSubtitle: Color(0xFFB8A878),
  cardBg: Color(0xFFF3ECD8), // 象牙
  cardBorder: Color(0xFFA89274),
  gold: Color(0xFF8B3A1D), // 赤茶（ブラス風）
  goldLight: Color(0xFFC98A5C),
  textPrimary: Color(0xFF2C2418), // 墨
  textSecondary: Color(0xFF5C4A32),
  bubbleUser: Color(0xFFDED4B8),
  bubbleAi: Color(0xFFF3ECD8),
  caseNumberFg: Color(0xFF1F3A2E),
);

/// テーマ名から AppColors を引く。
AppColors colorsOf(AppThemeName name) {
  switch (name) {
    case AppThemeName.detectiveLight:
      return _lightColors;
    case AppThemeName.detectiveDark:
      return _darkColors;
    case AppThemeName.study:
      return _studyColors;
  }
}

/// テーマ名から Flutter の ThemeData を組み立てる。
///
/// なぜ毎回ファクトリで組み立てるか：
/// ThemeData 全体を const で持てない（GoogleFonts などが絡む）ため、
/// 関数として一度だけ生成する。切替時に新しい ThemeData を MaterialApp.theme に差し込む。
ThemeData buildTheme(AppThemeName name) {
  final c = colorsOf(name);
  final isDark = name == AppThemeName.detectiveDark;

  final base = isDark ? ThemeData.dark() : ThemeData.light();

  return base.copyWith(
    brightness: isDark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: c.background,
    // ColorScheme は Material ウィジェットの内部で参照されるので、
    // AppColors と噛み合う値を入れておく（Switch の thumb など）。
    colorScheme: (isDark
            ? ColorScheme.dark(
                primary: c.gold,
                secondary: c.goldLight,
                surface: c.cardBg,
                onPrimary: c.appBarFg,
                onSurface: c.textPrimary,
              )
            : ColorScheme.light(
                primary: c.gold,
                secondary: c.goldLight,
                surface: c.cardBg,
                onPrimary: Colors.white,
                onSurface: c.textPrimary,
              ))
        .copyWith(),
    appBarTheme: AppBarTheme(
      backgroundColor: c.appBarBg,
      foregroundColor: c.appBarFg,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: c.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: c.cardBorder),
      ),
    ),
    dividerTheme: DividerThemeData(color: c.cardBorder),
    // ThemeExtension 経由でドメイン固有トークンを配信
    extensions: <ThemeExtension<dynamic>>[c],
  );
}
