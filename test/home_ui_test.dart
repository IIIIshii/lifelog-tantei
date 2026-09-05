import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nikkinext/core/streak.dart';
import 'package:nikkinext/core/theme/app_theme.dart';
import 'package:nikkinext/widgets/case_archive_tile.dart';

// ホーム画面のヒーローカードが表示する「連続日数」と「週間ヒートマップ」の算出、
// および事件簿アーカイブと共用するタイルの描画を検証する。
//
// 日付境界（月またぎ・うるう年・今日まだ書いていない場合）は取り違えやすく、
// 表示が1日ずれても気づきにくいのでここで固めておく。
void main() {
  group('calcStreak', () {
    test('今日を含めて連続していれば今日から数える', () {
      final today = DateTime(2026, 9, 5);
      final written = {'2026-09-05', '2026-09-04', '2026-09-03'};
      expect(calcStreak(written, today), 3);
    });

    test('今日まだ書いていなければ昨日から数える（日中に0と表示させない）', () {
      final today = DateTime(2026, 9, 5);
      final written = {'2026-09-04', '2026-09-03'};
      expect(calcStreak(written, today), 2);
    });

    test('昨日も書いていなければ0', () {
      final today = DateTime(2026, 9, 5);
      final written = {'2026-09-03', '2026-09-02'};
      expect(calcStreak(written, today), 0);
    });

    test('記録が空なら0', () {
      expect(calcStreak(const {}, DateTime(2026, 9, 5)), 0);
    });

    test('月をまたいでも連続として数える', () {
      final today = DateTime(2026, 3, 1);
      final written = {'2026-03-01', '2026-02-28', '2026-02-27'};
      expect(calcStreak(written, today), 3);
    });

    test('うるう年の2月29日をまたげる', () {
      final today = DateTime(2028, 3, 1);
      final written = {'2028-03-01', '2028-02-29', '2028-02-28'};
      expect(calcStreak(written, today), 3);
    });

    test('時刻が入っていても日付だけで判定する', () {
      final today = DateTime(2026, 9, 5, 23, 59);
      expect(calcStreak({'2026-09-05'}, today), 1);
    });
  });

  group('recentDayFlags', () {
    test('古い順に並び、末尾が今日になる', () {
      final today = DateTime(2026, 9, 5);
      final flags = recentDayFlags({'2026-09-05', '2026-09-01'}, today, 7);
      // 8/30, 8/31, 9/1, 9/2, 9/3, 9/4, 9/5
      expect(flags, [false, false, true, false, false, false, true]);
    });

    test('要求した日数ぶん返す', () {
      expect(recentDayFlags(const {}, DateTime(2026, 9, 5), 7).length, 7);
    });
  });

  group('dateKey', () {
    test('Firestore のドキュメントIDと同じ0埋め形式になる', () {
      expect(dateKey(DateTime(2026, 1, 2)), '2026-01-02');
    });
  });

  group('CaseArchiveTile', () {
    testWidgets('日付を整形して表示し、本文をプレビューする', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(AppThemeName.detectiveLight),
          home: Scaffold(
            body: CaseArchiveTile(
              date: '2026-09-04',
              diary: '七時間の睡眠で一日が明けた。',
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('2026年09月04日'), findsOneWidget);
      expect(find.text('七時間の睡眠で一日が明けた。'), findsOneWidget);
    });

    testWidgets('本文が空なら代替テキストを出す', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(AppThemeName.detectiveDark),
          home: Scaffold(
            body: CaseArchiveTile(date: '2026-09-04', diary: '   ', onTap: () {}),
          ),
        ),
      );

      expect(find.text('（本文なし）'), findsOneWidget);
    });

    testWidgets('タップで onTap が呼ばれる', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(AppThemeName.study),
          home: Scaffold(
            body: CaseArchiveTile(
              date: '2026-09-04',
              diary: '本文',
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(CaseArchiveTile));
      expect(tapped, isTrue);
    });
  });
}
