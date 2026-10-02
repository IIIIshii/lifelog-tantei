import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nikkinext/core/theme/app_theme.dart';
import 'package:nikkinext/models/goal.dart';
import 'package:nikkinext/widgets/goal_case_tile.dart';

// 追跡中の事件の行が、ホーム（事務所タブ）と相談室ハブの両方で
// 期待どおりに出ることを検証する。
//
// ここを固める理由:
// この部品は目標が1件だけだった頃、ホームの中で3状態を1枚で受け持っていた。
// 複数件を並べる形に作り直したので、「どの目標を今日記録したか」のバッジと、
// 画面によって変わる右端の導線（シェブロン／メニュー）が取り違えられていないかを
// 機械で確かめておきたい。
void main() {
  const diet = Goal(
    id: 'diet',
    title: '3ヶ月で5kg減らす',
    metric: '62kg以下',
    actions: [
      GoalAction(id: 'w1', label: '体重', type: GoalActionType.numeric),
      GoalAction(id: 'g1', label: 'ジムに行く'),
    ],
  );

  Future<void> pump(WidgetTester tester, Widget tile) => tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(AppThemeName.detectiveLight),
      home: Scaffold(body: tile),
    ),
  );

  group('GoalCaseTile', () {
    testWidgets('タイトルと行動項目のチップを出す', (tester) async {
      await pump(
        tester,
        GoalCaseTile(goal: diet, recordedToday: false, onTap: () {}),
      );

      expect(find.text('3ヶ月で5kg減らす'), findsOneWidget);
      expect(find.text('体重'), findsOneWidget);
      expect(find.text('ジムに行く'), findsOneWidget);
    });

    testWidgets('footnote を渡さなければ見出しは「追跡中の事件」', (tester) async {
      await pump(
        tester,
        GoalCaseTile(goal: diet, recordedToday: false, onTap: () {}),
      );

      expect(find.text('追跡中の事件'), findsOneWidget);
    });

    testWidgets('footnote を渡すと見出しがその文面になる', (tester) async {
      await pump(
        tester,
        GoalCaseTile(
          goal: diet,
          recordedToday: false,
          footnote: '着手から12日 / 期限 2026-12-31',
          onTap: () {},
        ),
      );

      expect(find.text('着手から12日 / 期限 2026-12-31'), findsOneWidget);
      expect(find.text('追跡中の事件'), findsNothing);
    });

    testWidgets('本日の記録の有無でバッジが切り替わる', (tester) async {
      await pump(
        tester,
        GoalCaseTile(goal: diet, recordedToday: true, onTap: () {}),
      );
      expect(find.text('記録済み'), findsOneWidget);

      await pump(
        tester,
        GoalCaseTile(goal: diet, recordedToday: false, onTap: () {}),
      );
      expect(find.text('未着手'), findsOneWidget);
    });

    testWidgets('行動項目が無ければバッジを出さず、達成の基準を副文にする', (tester) async {
      await pump(
        tester,
        GoalCaseTile(
          goal: const Goal(id: 'x', title: '方針だけ', metric: '心穏やかに過ごす'),
          recordedToday: false,
          onTap: () {},
        ),
      );

      expect(find.text('記録済み'), findsNothing);
      expect(find.text('未着手'), findsNothing);
      expect(find.text('心穏やかに過ごす'), findsOneWidget);
    });

    testWidgets('onMenu が無ければ右端はシェブロン', (tester) async {
      await pump(
        tester,
        GoalCaseTile(goal: diet, recordedToday: false, onTap: () {}),
      );

      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      expect(find.byIcon(Icons.more_horiz), findsNothing);
    });

    testWidgets('onMenu があれば右端はメニューボタンになり、押すと呼ばれる', (tester) async {
      var menuCalls = 0;
      await pump(
        tester,
        GoalCaseTile(
          goal: diet,
          recordedToday: false,
          onTap: () {},
          onMenu: () => menuCalls++,
        ),
      );

      expect(find.byIcon(Icons.chevron_right), findsNothing);
      await tester.tap(find.byIcon(Icons.more_horiz));
      expect(menuCalls, 1);
    });

    testWidgets('行のタップと長押しがそれぞれ呼ばれる', (tester) async {
      var taps = 0;
      var menuCalls = 0;
      await pump(
        tester,
        GoalCaseTile(
          goal: diet,
          recordedToday: false,
          onTap: () => taps++,
          onMenu: () => menuCalls++,
        ),
      );

      await tester.tap(find.text('3ヶ月で5kg減らす'));
      expect(taps, 1);

      await tester.longPress(find.text('3ヶ月で5kg減らす'));
      expect(menuCalls, 1);
    });
  });
}
