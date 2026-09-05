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
  final Color gold; // アクセント（濃いめ）。文字・アイコンとして background / cardBg の上に置ける明度を保つ
  final Color goldLight; // アクセント（薄め）。**面（フォルダータブ・ナビの選択ピル）専用で、前景には使わない**
  final Color textPrimary; // 主要テキスト
  final Color textSecondary; // 補助テキスト
  final Color bubbleUser; // 会話：ユーザーの吹き出し背景
  final Color bubbleAi; // 会話：AIの吹き出し背景
  final Color caseNumberFg; // goldLight の面に乗る前景色（ケース番号・ナビ選択中のアイコン/ラベル）

  /// gold を塗りつぶしに使った要素の上に乗る前景色。
  ///
  /// なぜ専用トークンが必要か：
  /// 以前は主要ボタンが `foregroundColor: c.appBarFg` を流用していたが、
  /// appBarFg は「暗いインク色の AppBar に乗せる明るいクリーム」であり、
  /// ダークテーマの明るいゴールド地に乗せるとコントラスト比 1.69:1 まで落ちて読めなかった。
  /// gold の明暗はテーマごとに反転する（ライト＝濃い金／ダーク＝明るい金）ため、
  /// その上に乗る前景色もテーマごとに反転させる必要がある。
  final Color onAccent;

  /// 円グラフの扇形色。テーマの明度に合わせて切り替える。
  ///
  /// なぜトークン化するか：
  /// 以前は AnalyticsPage に6色をハードコードしており、テーマを切り替えても
  /// 追随しなかった。さらに明るい扇形に白のラベルを固定で乗せていたため
  /// 最悪 1.44:1 まで落ちていた。色をテーマ側に持たせ、ラベル色は
  /// 扇形の明度から算出する（AnalyticsPage の _labelOn を参照）。
  final List<Color> chartPalette;

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
    required this.onAccent,
    required this.chartPalette,
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
    Color? onAccent,
    List<Color>? chartPalette,
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
      onAccent: onAccent ?? this.onAccent,
      chartPalette: chartPalette ?? this.chartPalette,
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
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      // chartPalette はテーマ間で色数が一致する保証がないため要素ごとの補間はせず、
      // 中間点で切り替える。円グラフはテーマ切替アニメーション中の一瞬しか
      // 中間状態を見せないので、この単純化で実害はない。
      chartPalette: t < 0.5 ? chartPalette : other.chartPalette,
    );
  }
}

/// 任意の面色の上に置くラベル色（黒か白）を、コントラストが高い方から選ぶ。
///
/// なぜ「輝度がしきい値より上なら黒」ではないのか：
/// しきい値方式は境界付近で誤る。実際 0.45 をしきい値にすると琥珀色
/// (#A8742A) に白が選ばれて 4.04:1 まで落ちた。黒と白それぞれの
/// コントラスト比を実際に計算して大きい方を採れば、この取りこぼしは起きない。
///
/// 円グラフの扇形のように「色がデータ由来で事前に固定できない面」で使う。
Color labelColorOn(Color surface) {
  const dark = Color(0xFF121212);
  const light = Color(0xFFFFFFFF);
  final l = surface.computeLuminance();
  double ratio(Color other) {
    final o = other.computeLuminance();
    final hi = l > o ? l : o;
    final lo = l > o ? o : l;
    return (hi + 0.05) / (lo + 0.05);
  }

  return ratio(dark) >= ratio(light) ? dark : light;
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
