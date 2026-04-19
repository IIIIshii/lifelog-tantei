import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_theme.dart';

/// テーマ選択状態をアプリ全体で共有するためのコントローラ。
///
/// なぜ ValueNotifier + シングルトン構成か：
/// - テーマ切替は低頻度・グローバル状態なので Provider / Riverpod を導入するほど重くない
/// - ValueNotifier なら MaterialApp を ValueListenableBuilder で包むだけで反応できる
/// - シングルトンにすることで設定画面からも main.dart からも同じインスタンスを触れる
///
/// なぜ SharedPreferences か：
/// - 同期的（メモリキャッシュ）に読めるので、起動時のデフォルトテーマでの
///   "一瞬チカッとする"フラッシュを回避できる
/// - Firestore だと await が必要で、初回フレームが必ずデフォルトテーマになってしまう
class ThemeController {
  ThemeController._();

  /// アプリ全体で参照する唯一のインスタンス。
  static final ThemeController instance = ThemeController._();

  /// SharedPreferences のキー。hard-coded で良いが将来 prefix を付けやすいよう定数化。
  static const _prefsKey = 'app_theme_name';

  /// 現在選択中のテーマ。MaterialApp 側で ValueListenableBuilder で購読する。
  final ValueNotifier<AppThemeName> notifier =
      ValueNotifier<AppThemeName>(AppThemeName.detectiveLight);

  AppThemeName get current => notifier.value;

  /// 起動時に一度だけ呼ぶ。SharedPreferences から保存値を読み込み notifier を初期化する。
  /// 失敗しても例外を握りつぶしデフォルトテーマで続行する（起動失敗を避ける）。
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved == null) return;
      // enum.name で保存しているので同じ方法で復元する。
      // 不正値（enum にない文字列）が入っていた場合は orElse でデフォルトに戻す。
      final matched = AppThemeName.values.firstWhere(
        (e) => e.name == saved,
        orElse: () => AppThemeName.detectiveLight,
      );
      notifier.value = matched;
    } catch (_) {
      // 起動を止めないため SharedPreferences 例外は無視
    }
  }

  /// テーマを切り替え、同時に SharedPreferences に永続化する。
  Future<void> setTheme(AppThemeName name) async {
    notifier.value = name;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, name.name);
    } catch (_) {
      // 永続化失敗はUX上致命的ではないので黙殺（次回起動時にデフォルトに戻るだけ）
    }
  }
}
