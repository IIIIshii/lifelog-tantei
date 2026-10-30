import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nikkinext/core/ai_data_disclosure.dart';
import 'package:nikkinext/core/theme/app_theme.dart';
import 'package:nikkinext/pages/ai_data_notice_page.dart';

// AI へ送られる内容の一覧と、それを見せる画面を検証する。
//
// 一覧は「利用者に何を伝えているか」そのものなので、
// 空欄や重複が紛れ込んでも画面は壊れず、気づけない。ここで見張る。
void main() {
  group('aiDataItems', () {
    test('項目があり、どの欄も空ではない', () {
      expect(aiDataItems, isNotEmpty);
      for (final item in aiDataItems) {
        expect(item.label.trim(), isNotEmpty);
        expect(item.detail.trim(), isNotEmpty);
        expect(item.usedFor.trim(), isNotEmpty);
      }
    });

    test('項目名は重複しない', () {
      final labels = aiDataItems.map((e) => e.label).toList();
      expect(labels.toSet().length, labels.length);
    });

    test('日記・記録・会話が一覧に含まれる', () {
      final labels = aiDataItems.map((e) => e.label).join(',');
      expect(labels, contains('日記'));
      expect(labels, contains('記録'));
      expect(labels, contains('会話'));
    });

    test('条件つきで送られるもの（MBTI）は、その条件を注記している', () {
      final mbti = aiDataItems.firstWhere((e) => e.label.contains('MBTI'));
      expect(mbti.note, isNotEmpty);
    });
  });

  group('AiDataNoticePage', () {
    Future<void> pumpPage(WidgetTester tester) async {
      // 6項目が1画面に収まる縦長にする（ListView は画面外を描画しないため）
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(AppThemeName.detectiveLight),
          home: const AiDataNoticePage(),
        ),
      );
    }

    testWidgets('送信先と、すべての項目名を表示する', (tester) async {
      await pumpPage(tester);
      expect(find.textContaining(aiProviderName), findsWidgets);
      for (final item in aiDataItems) {
        expect(find.text(item.label), findsOneWidget);
      }
    });

    testWidgets('注記がある項目は注記も表示する', (tester) async {
      await pumpPage(tester);
      for (final item in aiDataItems.where((e) => e.note.isNotEmpty)) {
        expect(find.text(item.note), findsOneWidget);
      }
    });
  });
}
