import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nikkinext/core/theme/app_colors.dart';
import 'package:nikkinext/core/theme/app_theme.dart';

// ──────────────────────────────────────────────────────────────
// テーマのコントラスト検証。
//
// なぜテストにするのか：
// 「この色とこの色の組み合わせは読みにくい」は目視だと気づきにくく、
// 実際このアプリでも主要ボタンが 1.69:1（ほぼ判読不能）のまま運用されていた。
// 配色は主観の問題に見えて、実際には計算で判定できる。判定を自動化しておけば
// パレットを触るたびに人が全画面を見比べる必要がなくなる。
//
// 基準は WCAG 2.2 AA を採る。2026年時点で W3C 勧告なのは 2.2 であり、
// ADA・Section 508・EN 301 549 が参照するのも WCAG 2.x 系のため。
// （APCA は WCAG 3.0 ドラフト内の候補手法であり、まだ適合基準ではない）
//
// AppThemeName.values を走査しているので、テーマを追加すると自動的に
// 検証対象に入る。追加したテーマがここで落ちたら、それは配色の側を直す。
// ──────────────────────────────────────────────────────────────

/// 本文テキストに必要な比（WCAG 2.2 SC 1.4.3 Contrast (Minimum)）。
const _textMin = 4.5;

/// UI部品の輪郭・グラフなど非テキストに必要な比（SC 1.4.11 Non-text Contrast）。
const _uiMin = 3.0;

/// 2色のコントラスト比を WCAG の定義で求める。
///
/// Color.computeLuminance() は WCAG の相対輝度をそのまま返すので、
/// 明るい方を L1 として (L1 + 0.05) / (L2 + 0.05) を計算すればよい。
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// 検証する1組。fg が bg の上に描かれ、min 以上の比が要る。
typedef _Check = ({
  String label,
  Color Function(AppColors) fg,
  Color Function(AppColors) bg,
  double min,
});

/// アプリ内で実際に発生する前景/背景の組み合わせ。
///
/// ここに載っているのは「どこかの画面で本当にその重なりが起きている」ものだけ。
/// 使われていない組み合わせまで縛ると、パレットの自由度を無意味に削ってしまう。
const List<_Check> _checks = [
  // ── 本文・見出し ────────────────────────────────────────────
  (
    label: '本文 on 画面背景',
    fg: _textPrimary,
    bg: _background,
    min: _textMin
  ),
  (label: '本文 on カード', fg: _textPrimary, bg: _cardBg, min: _textMin),
  (
    label: '吹き出し本文（証言）',
    fg: _textPrimary,
    bg: _bubbleUser,
    min: _textMin
  ),
  (label: '吹き出し本文（探偵）', fg: _textPrimary, bg: _bubbleAi, min: _textMin),
  (
    label: '補助テキスト on 画面背景',
    fg: _textSecondary,
    bg: _background,
    min: _textMin
  ),
  (
    label: '補助テキスト on カード',
    fg: _textSecondary,
    bg: _cardBg,
    min: _textMin
  ),
  (
    label: '補助テキスト on 吹き出し',
    fg: _textSecondary,
    bg: _bubbleUser,
    min: _textMin
  ),

  // ── AppBar / ボトムナビ ─────────────────────────────────────
  (label: 'AppBarタイトル', fg: _appBarFg, bg: _appBarBg, min: _textMin),
  (
    label: 'AppBarサブタイトル / ナビ非選択',
    fg: _appBarSubtitle,
    bg: _appBarBg,
    min: _textMin
  ),
  (
    label: 'ナビ選択ピル vs バー',
    fg: _goldLight,
    bg: _appBarBg,
    min: _uiMin
  ),

  // ── アクセント（gold）────────────────────────────────────────
  // gold は 10〜13px の見出し・ラベルとして使われるので本文と同じ 4.5:1 が要る。
  (
    label: 'goldのラベル on 画面背景',
    fg: _gold,
    bg: _background,
    min: _textMin
  ),
  (label: 'goldのラベル on カード', fg: _gold, bg: _cardBg, min: _textMin),
  (
    label: 'goldのラベル on 吹き出し',
    fg: _gold,
    bg: _bubbleUser,
    min: _textMin
  ),
  // 主要ボタン・FAB・送信ボタン・Switchのつまみが全部この1組に集約される。
  (label: '主要ボタンのラベル on gold', fg: _onAccent, bg: _gold, min: _textMin),
  // フォルダータブのケース番号、ボトムナビの選択中アイコン/ラベル。
  (
    label: 'goldLightの面に乗る前景',
    fg: _caseNumberFg,
    bg: _goldLight,
    min: _textMin
  ),

  // ── 輪郭（SC 1.4.11）─────────────────────────────────────────
  // カード面と背景の明度差は小さくてよい。輪郭はこの枠線が担う。
  (label: 'カード枠線 vs 画面背景', fg: _cardBorder, bg: _background, min: _uiMin),
  (label: 'カード枠線 vs カード面', fg: _cardBorder, bg: _cardBg, min: _uiMin),
  (
    label: '吹き出し枠線 vs 吹き出し（証言）',
    fg: _cardBorder,
    bg: _bubbleUser,
    min: _uiMin
  ),
  (
    label: '吹き出し枠線 vs 吹き出し（探偵）',
    fg: _cardBorder,
    bg: _bubbleAi,
    min: _uiMin
  ),

  // ── アイコン・グラフ（非テキスト）───────────────────────────
  (label: 'goldのアイコン vs 画面背景', fg: _gold, bg: _background, min: _uiMin),
  (label: 'グラフの棒 vs カード', fg: _gold, bg: _cardBg, min: _uiMin),
];

// 上の const リストから参照するためのトップレベル関数群。
// （const 式の中ではクロージャを書けないため）
Color _background(AppColors c) => c.background;
Color _appBarBg(AppColors c) => c.appBarBg;
Color _appBarFg(AppColors c) => c.appBarFg;
Color _appBarSubtitle(AppColors c) => c.appBarSubtitle;
Color _cardBg(AppColors c) => c.cardBg;
Color _cardBorder(AppColors c) => c.cardBorder;
Color _gold(AppColors c) => c.gold;
Color _goldLight(AppColors c) => c.goldLight;
Color _textPrimary(AppColors c) => c.textPrimary;
Color _textSecondary(AppColors c) => c.textSecondary;
Color _bubbleUser(AppColors c) => c.bubbleUser;
Color _bubbleAi(AppColors c) => c.bubbleAi;
Color _caseNumberFg(AppColors c) => c.caseNumberFg;
Color _onAccent(AppColors c) => c.onAccent;

void main() {
  for (final name in AppThemeName.values) {
    group('テーマ: ${name.name}', () {
      final c = colorsOf(name);

      for (final check in _checks) {
        test('${check.label} は ${check.min}:1 以上', () {
          final ratio = _contrast(check.fg(c), check.bg(c));
          expect(
            ratio,
            greaterThanOrEqualTo(check.min),
            reason: '${check.label}: '
                '${_hex(check.fg(c))} on ${_hex(check.bg(c))} = '
                '${ratio.toStringAsFixed(2)}:1 '
                '(必要 ${check.min}:1)',
          );
        });
      }

      test('円グラフ: 全扇形がカード面と 3:1、ラベルが扇形と 4.5:1', () {
        expect(c.chartPalette, isNotEmpty);
        for (final slice in c.chartPalette) {
          final vsCard = _contrast(slice, c.cardBg);
          expect(
            vsCard,
            greaterThanOrEqualTo(_uiMin),
            reason: '扇形 ${_hex(slice)} がカード面 ${_hex(c.cardBg)} に対し '
                '${vsCard.toStringAsFixed(2)}:1',
          );

          final vsLabel = _contrast(labelColorOn(slice), slice);
          expect(
            vsLabel,
            greaterThanOrEqualTo(_textMin),
            reason: '扇形 ${_hex(slice)} 上のパーセント表示が '
                '${vsLabel.toStringAsFixed(2)}:1',
          );
        }
      });
    });
  }

  test('ダーク判定が全テーマで矛盾しない', () {
    // 背景が暗いのに isDarkTheme が false（またはその逆）だと
    // ThemeData.dark()/light() の選択がずれ、指定漏れの色だけが逆転する。
    for (final name in AppThemeName.values) {
      final c = colorsOf(name);
      expect(
        isDarkTheme(name),
        c.background.computeLuminance() < 0.2,
        reason: '${name.name}: 背景の輝度と isDarkTheme() が食い違っている',
      );
    }
  });
}

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
