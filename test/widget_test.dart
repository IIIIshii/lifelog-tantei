import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nikkinext/core/theme/app_theme.dart';
import 'package:nikkinext/widgets/diary_card.dart';

void main() {
  testWidgets('DiaryCard shows placeholder for an empty diary', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(AppThemeName.detectiveLight),
        home: const Scaffold(
          body: DiaryCard(diary: ''),
        ),
      ),
    );

    expect(find.text('事件報告書'), findsOneWidget);
    expect(find.text('（本文なし）'), findsOneWidget);
  });
}
