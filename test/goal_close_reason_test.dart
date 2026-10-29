import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nikkinext/core/goal_digest.dart';
import 'package:nikkinext/models/goal.dart';
import 'package:nikkinext/prompts/ai_instructions.dart';
import 'package:nikkinext/prompts/goal_prompts.dart';
import 'package:nikkinext/widgets/close_goal_dialog.dart';

// 目標を終えるときの「理由」を検証する。
//
// 理由は、続かなかった事実の意味（大きすぎた／興味が薄れた）を分けるための手がかり。
// 保存・読み戻し・AI への受け渡し・下書きの扱い（利用者の入力を上書きしない）を固める。
void main() {
  group('Goal.closeReason', () {
    test('理由を持たない既存のデータは、空文字として読める', () {
      final goal = Goal.fromMap({
        'id': 'g',
        'title': '走る',
        'status': 'abandoned',
      });
      expect(goal.closeReason, '');
    });

    test('保存して読み戻しても、理由が残る', () {
      const goal = Goal(
        id: 'g',
        title: '走る',
        status: GoalStatus.abandoned,
        closedAt: '2026-10-20',
        closeReason: '朝は時間が取れなかった',
      );
      final loaded = Goal.fromMap(goal.toMap());
      expect(loaded.closeReason, '朝は時間が取れなかった');
    });

    test('copyWith で理由だけを変えられる', () {
      const goal = Goal(id: 'g', title: '走る', closeReason: '前の理由');
      expect(goal.copyWith(closeReason: '新しい理由').closeReason, '新しい理由');
      expect(goal.copyWith(title: '歩く').closeReason, '前の理由');
    });
  });

  group('closedGoalsDigest の理由', () {
    test('理由があれば添え、無ければ添えない', () {
      const withReason = Goal(
        id: 'a',
        title: '毎朝走る',
        status: GoalStatus.abandoned,
        createdAt: '2026-09-01',
        closedAt: '2026-09-20',
        closeReason: '朝は時間が取れなかった',
      );
      const withoutReason = Goal(
        id: 'b',
        title: '本を読む',
        status: GoalStatus.solved,
        createdAt: '2026-08-01',
        closedAt: '2026-09-01',
      );
      final lines = closedGoalsDigest([withReason, withoutReason]).split('\n');
      expect(
        lines[0],
        '- 目標「毎朝走る」: 断念した（2026-09-01〜2026-09-20）。理由: 朝は時間が取れなかった',
      );
      expect(lines[1], '- 目標「本を読む」: 解決した（2026-08-01〜2026-09-01）');
    });

    test('空白だけの理由は、理由なしとして扱う', () {
      const goal = Goal(
        id: 'a',
        title: '毎朝走る',
        status: GoalStatus.abandoned,
        closeReason: '   ',
      );
      expect(closedGoalsDigest([goal]), isNot(contains('理由')));
    });
  });

  group('理由の下書きのプロンプト', () {
    test('目標・終え方・続き具合・最近の日記を渡す', () {
      final prompt = GoalPrompts.buildCloseReasonPrompt(
        goalSummary: '- 目標: 毎朝走る',
        outcome: '断念した（追跡をやめた）',
        continuity: '  - 「走る」: 週ごとの達成日数/記録日数 4/5 → 0/0',
        recentDiaries: ['残業で帰りが遅かった'],
      );
      expect(prompt, contains('【終える目標】\n- 目標: 毎朝走る'));
      expect(prompt, contains('【終え方】\n断念した（追跡をやめた）'));
      expect(prompt, contains('4/5 → 0/0'));
      expect(prompt, contains('- 残業で帰りが遅かった'));
    });

    test('続き具合・日記が無ければ、その節は付けない', () {
      final prompt = GoalPrompts.buildCloseReasonPrompt(
        goalSummary: '- 目標: 毎朝走る',
        outcome: '解決した',
      );
      expect(prompt, isNot(contains('【続き具合')));
      expect(prompt, isNot(contains('【最近の日記】')));
    });

    test('指示は、断定させず・作り話で埋めさせず・責めさせない', () {
      final rules = AiInstructions.closeReasonDrafter();
      expect(rules, contains('断定しない'));
      expect(rules, contains('何も書かず空の文字列を返す'));
      expect(rules, contains('責めない'));
    });
  });

  group('cleanCloseReason', () {
    test('前後の空白と、全体を囲むかぎ括弧・引用符を外す', () {
      expect(GoalPrompts.cleanCloseReason('  「忙しかったようだ」 '), '忙しかったようだ');
      expect(GoalPrompts.cleanCloseReason('"busy"'), 'busy');
    });

    test('文の途中のかぎ括弧は外さない', () {
      expect(GoalPrompts.cleanCloseReason('「朝」は忙しかった'), '「朝」は忙しかった');
    });

    test('長すぎるものは切る', () {
      final long = 'あ' * 200;
      expect(GoalPrompts.cleanCloseReason(long).length, 120);
    });

    test('空は空のまま', () {
      expect(GoalPrompts.cleanCloseReason('  '), '');
    });
  });

  group('CloseGoalDialog', () {
    const goal = Goal(id: 'g', title: '毎朝走る');

    // ダイアログを開き、確定したときの戻り値を result に入れる
    Future<void> open(
      WidgetTester tester,
      Future<String> draft,
      void Function(String?) onResult,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    final value = await showDialog<String>(
                      context: context,
                      builder: (_) => CloseGoalDialog(
                        goal: goal,
                        solved: false,
                        draft: draft,
                      ),
                    );
                    onResult(value);
                  },
                  child: const Text('開く'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('開く'));
      await tester.pumpAndSettle();
    }

    testWidgets('下書きができたら欄に入り、そのまま確定すると理由として返る', (tester) async {
      final completer = Completer<String>();
      String? result = 'unset';
      await open(tester, completer.future, (v) => result = v);

      expect(find.text('下書きを作っている…'), findsOneWidget);

      completer.complete('朝は時間が取れなかったのかもしれない');
      // 補助文の入れ替えはアニメーションなので、終わるまで待つ
      await tester.pumpAndSettle();
      expect(find.text('朝は時間が取れなかったのかもしれない'), findsOneWidget);
      expect(find.textContaining('AIの下書き'), findsOneWidget);

      await tester.tap(find.text('追跡をやめる'));
      await tester.pumpAndSettle();
      expect(result, '朝は時間が取れなかったのかもしれない');
    });

    testWidgets('利用者が先に書き始めたら、あとから来た下書きで上書きしない', (tester) async {
      final completer = Completer<String>();
      String? result = 'unset';
      await open(tester, completer.future, (v) => result = v);

      await tester.enterText(find.byType(TextField), '仕事が忙しかった');
      completer.complete('AIの下書き文');
      await tester.pump();

      expect(find.text('仕事が忙しかった'), findsOneWidget);
      expect(find.text('AIの下書き文'), findsNothing);

      await tester.tap(find.text('追跡をやめる'));
      await tester.pumpAndSettle();
      expect(result, '仕事が忙しかった');
    });

    testWidgets('下書きが空なら、欄は空のまま。理由なしで閉じられる', (tester) async {
      String? result = 'unset';
      await open(tester, Future.value(''), (v) => result = v);
      await tester.pumpAndSettle();

      expect(find.textContaining('AIの下書き'), findsNothing);
      expect(find.text('下書きを作っている…'), findsNothing);
      await tester.tap(find.text('追跡をやめる'));
      await tester.pumpAndSettle();
      expect(result, '');
    });

    testWidgets('下書きを直してから確定すると、直した内容が返る', (tester) async {
      String? result = 'unset';
      await open(tester, Future.value('下書き'), (v) => result = v);
      await tester.pumpAndSettle();
      expect(find.textContaining('AIの下書き'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '  自分で書いた理由  ');
      await tester.pumpAndSettle();
      expect(find.textContaining('AIの下書き'), findsNothing);

      await tester.tap(find.text('追跡をやめる'));
      await tester.pumpAndSettle();
      expect(result, '自分で書いた理由');
    });

    testWidgets('キャンセルは null を返す（理由が空の確定とは区別される）', (tester) async {
      String? result = 'unset';
      await open(tester, Future.value('下書き'), (v) => result = v);

      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });
  });
}
