import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nikkinext/core/theme/app_theme.dart';
import 'package:nikkinext/models/archive_month.dart';
import 'package:nikkinext/widgets/archive_book.dart';

Widget host(AppThemeName theme, ArchiveMonth month, VoidCallback onTap) {
  return MaterialApp(
    theme: buildTheme(theme),
    home: Scaffold(
      body: SizedBox(
        width: 163,
        height: 186,
        child: ArchiveBook(month: month, onTap: onTap),
      ),
    ),
  );
}

void main() {
  const sep = ArchiveMonth(year: 2026, month: 9, count: 22);

  testWidgets('年・月・件数を表示する', (tester) async {
    await tester.pumpWidget(host(AppThemeName.detectiveDark, sep, () {}));

    expect(find.text('2026'), findsOneWidget);
    expect(find.text('9月'), findsOneWidget);
    expect(find.text('22件の事件'), findsOneWidget);
  });

  testWidgets('タップで onTap が呼ばれる', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      host(AppThemeName.detectiveLight, sep, () => tapped = true),
    );

    await tester.tap(find.byType(ArchiveBook));
    expect(tapped, isTrue);
  });

  testWidgets('全テーマ・全12か月で例外なく描画できる（パレット巡回の境界）', (tester) async {
    for (final theme in AppThemeName.values) {
      for (var m = 1; m <= 12; m++) {
        await tester.pumpWidget(
          host(theme, ArchiveMonth(year: 2026, month: m, count: 1), () {}),
        );
        expect(tester.takeException(), isNull, reason: '$theme $m月');
      }
    }
  });
}
