import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nikkinext/core/theme/app_theme.dart';
import 'package:nikkinext/pages/diary_month_page.dart';
import 'package:nikkinext/widgets/case_archive_tile.dart';

Widget host({
  required int year,
  required int month,
  required Map<String, String> entries,
  void Function(String, String)? onOpenDetail,
}) {
  return MaterialApp(
    theme: buildTheme(AppThemeName.detectiveDark),
    home: DiaryMonthPage(
      year: year,
      month: month,
      entries: Stream.value(entries),
      onOpenDetail: onOpenDetail ?? (_, _) {},
    ),
  );
}

const sepEntries = {
  '2026-09-03': '三日の日記',
  '2026-09-05': '五日の日記',
  '2026-09-22': '二十二日の日記',
  '2026-08-31': '八月の日記', // 他の月は無視される
};

void main() {
  testWidgets('初期状態では月内で最新の日記がプレビューされる', (tester) async {
    await tester.pumpWidget(host(year: 2026, month: 9, entries: sepEntries));
    await tester.pump();

    expect(find.text('二十二日の日記'), findsOneWidget);
    expect(find.text('八月の日記'), findsNothing);
    expect(find.text('9月の事件簿'), findsOneWidget);
    expect(find.text('― 2026年 ―'), findsOneWidget);
  });

  group('AppBar（戻るボタンの置き場）', () {
    // 読み込み中・エラー時に AppBar ごと消えると、画面に戻るボタンが無くなる
    // 本棚から push された状態を再現する（戻るボタンは「前の画面がある」ときだけ出る）。
    // 読み込み中のスピナーは回り続けるので、pumpAndSettle は使えず pump で時間を進める
    Future<void> pushMonthPage(
      WidgetTester tester,
      Stream<Map<String, String>> stream,
    ) async {
      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          theme: buildTheme(AppThemeName.detectiveDark),
          home: const Scaffold(body: Text('本棚')),
        ),
      );
      navKey.currentState!.push(
        MaterialPageRoute(
          builder: (_) => DiaryMonthPage(
            year: 2026,
            month: 9,
            entries: stream,
            onOpenDetail: (_, _) {},
          ),
        ),
      );
      // 遷移アニメーションは、1回目の pump で開始し、2回目の pump で進む
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('読み込み中でも AppBar と戻るボタンが出る', (tester) async {
      await pushMonthPage(tester, const Stream.empty());

      expect(find.text('9月の事件簿'), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
    });

    testWidgets('エラー時でも AppBar と戻るボタンが出る', (tester) async {
      await pushMonthPage(tester, Stream.error('失敗'));

      expect(find.text('エラー: 失敗'), findsOneWidget);
      expect(find.text('9月の事件簿'), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
    });
  });

  testWidgets('日記のある日をタップするとプレビューが切り替わる', (tester) async {
    await tester.pumpWidget(host(year: 2026, month: 9, entries: sepEntries));
    await tester.pump();

    await tester.tap(find.text('5'));
    await tester.pumpAndSettle();

    expect(find.text('五日の日記'), findsOneWidget);
    expect(find.text('二十二日の日記'), findsNothing);
  });

  testWidgets('日記のない日をタップしても選択は変わらない', (tester) async {
    await tester.pumpWidget(host(year: 2026, month: 9, entries: sepEntries));
    await tester.pump();

    await tester.tap(find.text('10'));
    await tester.pumpAndSettle();

    expect(find.text('二十二日の日記'), findsOneWidget);
  });

  testWidgets('プレビューをタップすると日付と本文つきで詳細遷移が呼ばれる', (tester) async {
    String? date;
    String? diary;
    await tester.pumpWidget(
      host(
        year: 2026,
        month: 9,
        entries: sepEntries,
        onOpenDetail: (d, t) {
          date = d;
          diary = t;
        },
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(CaseArchiveTile));

    expect(date, '2026-09-22');
    expect(diary, '二十二日の日記');
  });

  testWidgets('画面外のプレビューは、日付タップで見える位置まで自動スクロールされる', (tester) async {
    tester.view.physicalSize = const Size(320, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(year: 2026, month: 9, entries: sepEntries));
    await tester.pump();

    final before = tester.getRect(find.byType(CaseArchiveTile));
    expect(before.bottom, greaterThan(400), reason: '前提: 最初はプレビューが画面外');

    await tester.tap(find.text('5'));
    await tester.pumpAndSettle();

    final after = tester.getRect(find.byType(CaseArchiveTile));
    expect(after.bottom, lessThanOrEqualTo(400));
  });

  group('月の日数と週数', () {
    testWidgets('うるう年の2月は29日まで、平年は28日まで表示する', (tester) async {
      await tester.pumpWidget(host(year: 2024, month: 2, entries: const {}));
      await tester.pump();
      expect(find.text('29'), findsOneWidget);

      await tester.pumpWidget(host(year: 2025, month: 2, entries: const {}));
      await tester.pump();
      expect(find.text('28'), findsOneWidget);
      expect(find.text('29'), findsNothing);
    });

    testWidgets('6週にまたがる月（2026年8月）も例外なく描画できる', (tester) async {
      await tester.pumpWidget(
        host(year: 2026, month: 8, entries: const {'2026-08-31': '末日'}),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('31'), findsOneWidget);
    });
  });

  testWidgets('その月の記録が無ければ代替テキストを出す', (tester) async {
    await tester.pumpWidget(host(year: 2026, month: 9, entries: const {}));
    await tester.pump();

    expect(find.text('この月の記録はありません'), findsOneWidget);
  });
}
