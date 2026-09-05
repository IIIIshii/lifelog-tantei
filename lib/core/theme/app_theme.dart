import 'package:flutter/material.dart';
import 'app_colors.dart';

/// 選択可能なテーマの列挙。
/// SharedPreferences に保存する際は .name を key として使う。
enum AppThemeName {
  detectiveLight, // 探偵（ライト・セピア）
  detectiveDark, // ダーク（ノワール）
  study, // 書斎（ブリティッシュグリーン + ブラス）
  forensicBlueprint, // 鑑識（ダーク・青写真 + シアン）
  dossierHighContrast, // 調書（ライト・白紙 + 朱印 / 最も読みやすい）
}

/// そのテーマが暗い配色かどうか。
///
/// なぜ enum の比較を直に書かないか：
/// 以前は `name == AppThemeName.detectiveDark` と1テーマ名を直接比較していたため、
/// ダークテーマを追加した時点で ThemeData.dark() が選ばれず破綻する構造だった。
/// 明度は「テーマの属性」なので、判定を1か所に集約して追加時の漏れを防ぐ。
bool isDarkTheme(AppThemeName name) =>
    name == AppThemeName.detectiveDark ||
    name == AppThemeName.forensicBlueprint;

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
      case AppThemeName.forensicBlueprint:
        return '鑑識（ダーク / ブループリント）';
      case AppThemeName.dossierHighContrast:
        return '調書（高コントラスト）';
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
      case AppThemeName.forensicBlueprint:
        return '深夜の鑑識室。青写真の紺とシアンの光';
      case AppThemeName.dossierHighContrast:
        return '白紙と朱印。最も文字が読みやすい設定';
    }
  }
}

/// ── カラーパレット定義 ──────────────────────────────────────
/// 各テーマは AppColors インスタンスとして定義し、buildTheme() で ThemeData に焼き付ける。
///
/// 全テーマの全ペアが WCAG 2.2 AA（本文 4.5:1 / 非テキスト 3:1）を満たすことを
/// test/theme_contrast_test.dart で機械的に検証している。値を変更したらテストを回すこと。
///
/// 設計の要点：
/// - 面（cardBg）と背景（background）の明度差は小さくてよい。カード・吹き出しの
///   「輪郭」は cardBorder が担い、cardBorder を隣接色に対して 3:1 以上に保つ
///   （WCAG SC 1.4.11）。以前は枠線が 1.5:1 程度しかなく、画面全体が
///   のっぺりした一枚の色面に見えていた。
/// - gold は「文字・アイコンとして使う濃さ」、goldLight は「面として使う薄さ」と
///   役割を完全に分離する。両者を入れ替えて使ってはいけない。

// 円グラフの扇形色。テーマの明度別に2セット用意し、各テーマがどちらかを参照する。
// いずれも cardBg に対して 3:1 以上（グラフの意味ある部分＝ SC 1.4.11）を確保している。
const _lightChart = <Color>[
  Color(0xFF6E5210), // 金褐
  Color(0xFFA8742A), // 琥珀
  Color(0xFF4A6B3A), // 深緑
  Color(0xFF8C4A2F), // 赤錆
  Color(0xFF3F5C6B), // 藍鼠
  Color(0xFF7A5C86), // 葡萄
];

const _darkChart = <Color>[
  Color(0xFFE0BE63),
  Color(0xFFD89A5A),
  Color(0xFF8FC98F),
  Color(0xFFE8907C),
  Color(0xFF7FD4E8),
  Color(0xFFC4A2E0),
];

// 探偵（ライト・セピア）
// bubbleAi = カード色と同じクリーム / bubbleUser = それより一段濃いタン
// テキストは双方 textPrimary（黒系）で可読性を確保
const _lightColors = AppColors(
  background: Color(0xFFE9DECA), // 古い羊皮紙（枠線が乗る余地を作るため旧値より一段濃い）
  appBarBg: Color(0xFF2C1A0E), // 濃いインク
  appBarFg: Color(0xFFF2E9D8),
  appBarSubtitle: Color(0xFFC7AC7E),
  cardBg: Color(0xFFFBF6EC), // クリーム
  cardBorder: Color(0xFF806A48), // 背景に対し 3.87:1。書類の罫線として輪郭を担う
  gold: Color(0xFF6E5210), // 12px の見出しにも使うので 4.5:1 を満たす濃さにする
  goldLight: Color(0xFFD8BC72), // 面専用（フォルダータブ / ナビの選択ピル）
  textPrimary: Color(0xFF1A0F05),
  textSecondary: Color(0xFF5A3F22),
  bubbleUser: Color(0xFFE3D6C0), // 一段濃いタン
  bubbleAi: Color(0xFFFBF6EC),
  caseNumberFg: Color(0xFF241407),
  onAccent: Color(0xFFFFFFFF), // 濃い金地の上なので白
  chartPalette: _lightChart,
);

// 探偵（ダーク・ノワール）
// bubbleAi = カード色と同じ焦茶 / bubbleUser = ひとつ明るいブラウン
// テキストは双方 textPrimary（クリーム）
const _darkColors = AppColors(
  background: Color(0xFF16100A), // 深いインク
  appBarBg: Color(0xFF0B0705), // 漆黒
  appBarFg: Color(0xFFF0E7D6),
  appBarSubtitle: Color(0xFFCBB183),
  cardBg: Color(0xFF241A11), // 焦茶
  cardBorder: Color(0xFF9A8158), // 暗い面の上で輪郭を出すため旧値より大幅に明るくする
  gold: Color(0xFFE0BE63), // ダーク時は明るい金
  goldLight: Color(0xFFC6A455), // 面専用。暗いバーの上でピルが見えるだけの明度を持たせる
  textPrimary: Color(0xFFF0E7D6), // クリーム
  textSecondary: Color(0xFFCBB183),
  bubbleUser: Color(0xFF35271A), // ひとつ明るいブラウン
  bubbleAi: Color(0xFF241A11),
  caseNumberFg: Color(0xFF1A1204), // 明るい goldLight の面に乗るので暗色
  onAccent: Color(0xFF140E04), // 明るい金地の上なので暗色（旧実装のクリームは 1.69:1 だった）
  chartPalette: _darkChart,
);

// 書斎（ブリティッシュグリーン + ブラス）
const _studyColors = AppColors(
  background: Color(0xFFE4DBC0), // 古紙
  appBarBg: Color(0xFF1B342A), // ブリティッシュグリーン
  appBarFg: Color(0xFFEFE8D2),
  appBarSubtitle: Color(0xFFC4B487),
  cardBg: Color(0xFFF5EFDD), // 象牙
  cardBorder: Color(0xFF7C6B4C),
  gold: Color(0xFF7E3418), // 赤茶（ブラス風）
  goldLight: Color(0xFFD8A97E),
  textPrimary: Color(0xFF241E14), // 墨
  textSecondary: Color(0xFF53432C),
  bubbleUser: Color(0xFFDCD2B6),
  bubbleAi: Color(0xFFF5EFDD),
  caseNumberFg: Color(0xFF1B342A),
  onAccent: Color(0xFFFFFFFF),
  chartPalette: _lightChart,
);

// 鑑識（ダーク・青写真 + シアン）
// ノワールと同じ暗さでも色相が真逆なので、セピアに飽きた場合の選択肢になる。
// 寒色は暖色より「沈んで」見えるため、アクセントのシアンは明度を高めに取る。
const _forensicColors = AppColors(
  background: Color(0xFF0E1620), // 夜の鑑識室
  appBarBg: Color(0xFF060B12),
  appBarFg: Color(0xFFE3ECF5),
  appBarSubtitle: Color(0xFF9FB6CC),
  cardBg: Color(0xFF18232F), // 青写真の紙
  cardBorder: Color(0xFF6E8AA6),
  gold: Color(0xFF7FD4E8), // 検出光のシアン（トークン名は gold だが役割はアクセント）
  goldLight: Color(0xFFA9CBDB), // 面専用
  textPrimary: Color(0xFFE3ECF5),
  textSecondary: Color(0xFF9FB6CC),
  bubbleUser: Color(0xFF24323F),
  bubbleAi: Color(0xFF18232F),
  caseNumberFg: Color(0xFF061620),
  onAccent: Color(0xFF04121A),
  chartPalette: _darkChart,
);

// 調書（高コントラスト）
// 世界観より可読性を優先したい人向け。白紙に黒インク、朱肉の赤を1点だけ効かせる。
// 本文 16.44:1 と全テーマ中で最も高い。
const _dossierColors = AppColors(
  background: Color(0xFFF2F0EA), // わずかに温かみのある白
  appBarBg: Color(0xFF1A1A1A),
  appBarFg: Color(0xFFFAFAF8),
  appBarSubtitle: Color(0xFFC9C6BE),
  cardBg: Color(0xFFFFFFFF), // 純白の紙
  cardBorder: Color(0xFF6E6E6A),
  gold: Color(0xFF9A2216), // 朱印
  goldLight: Color(0xFFF0D6D2), // 面専用（淡い朱）
  textPrimary: Color(0xFF121212),
  textSecondary: Color(0xFF474744),
  bubbleUser: Color(0xFFE6E3DB),
  bubbleAi: Color(0xFFFFFFFF),
  caseNumberFg: Color(0xFF121212),
  onAccent: Color(0xFFFFFFFF),
  chartPalette: _lightChart,
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
    case AppThemeName.forensicBlueprint:
      return _forensicColors;
    case AppThemeName.dossierHighContrast:
      return _dossierColors;
  }
}

/// テーマ名から Flutter の ThemeData を組み立てる。
///
/// なぜ毎回ファクトリで組み立てるか：
/// ThemeData 全体を const で持てない（GoogleFonts などが絡む）ため、
/// 関数として一度だけ生成する。切替時に新しい ThemeData を MaterialApp.theme に差し込む。
ThemeData buildTheme(AppThemeName name) {
  final c = colorsOf(name);
  final isDark = isDarkTheme(name);

  final base = isDark ? ThemeData.dark() : ThemeData.light();

  return base.copyWith(
    brightness: isDark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: c.background,
    // ColorScheme は Material ウィジェットの内部で参照されるので、
    // AppColors と噛み合う値を入れておく（Switch の thumb など）。
    //
    // outline / onSurfaceVariant / surfaceContainerHighest まで埋める理由：
    // ここを空けておくと AlertDialog・SnackBar・TimePicker が M3 デフォルトの
    // パープル系ベースラインで描かれ、探偵テーマから浮いてしまう。
    colorScheme: (isDark ? ColorScheme.dark : ColorScheme.light)(
      primary: c.gold,
      secondary: c.goldLight,
      surface: c.cardBg,
      // onPrimary は「gold の上に乗る色」。以前はライト=白／ダーク=クリームと
      // 非対称で、ダークでは 1.69:1 しかなかった。onAccent に一本化する。
      onPrimary: c.onAccent,
      onSurface: c.textPrimary,
      onSurfaceVariant: c.textSecondary,
      outline: c.cardBorder,
      surfaceContainerHighest: c.cardBg,
    ),
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

    // ── ボトムナビゲーション ──────────────────────────────────
    // AppBar と同じインク色を敷き、画面の上下を「事務所の看板」で挟む構図にする。
    // 構造は Material 3 標準の NavigationBar のまま、世界観は色だけで表現する
    // （見慣れた配置を崩さないほうがユーザビリティを損なわない、という方針）。
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.appBarBg,
      // 選択インジケーター（ピル）は goldLight を不透明で敷く。
      //
      // なぜ gold の半透明をやめたか：
      // gold はライトテーマでは濃い金（#6E5210）で、暗いインク色のバーの上に
      // 35% で重ねてもバーとの差が 1.10〜1.30:1 にしかならず、どのタブが
      // 選択中なのか事実上見えなかった。goldLight は「暗い面の上に敷く明るい面」
      // として定義したトークンなので、こちらを使えばバーに対して 3:1 以上が出る。
      indicatorColor: c.goldLight,
      elevation: 0,
      // 選択中はピル（goldLight）の上に乗るので caseNumberFg、
      // 非選択はバー（appBarBg）の上に乗るので appBarSubtitle。
      // 「乗っている面が違えば前景色も違う」という当たり前を明示的に書く。
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 11,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          color: selected ? c.caseNumberFg : c.appBarSubtitle,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: 24,
          color: selected ? c.caseNumberFg : c.appBarSubtitle,
        );
      }),
    ),

    // ── FAB（主要動線「捜査を開始する」） ────────────────────
    // かつて isDark で明暗を出し分けていた処理は onAccent トークンが引き受けた。
    // 「gold の上に何を乗せれば読めるか」はテーマ自身が知っているべき情報で、
    // 使う側が明度から推測するものではない。
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: c.gold,
      foregroundColor: c.onAccent,
      elevation: 2,
    ),

    // ThemeExtension 経由でドメイン固有トークンを配信
    extensions: <ThemeExtension<dynamic>>[c],
  );
}
