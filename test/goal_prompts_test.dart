import 'package:flutter_test/flutter_test.dart';
import 'package:nikkinext/prompts/goal_prompts.dart';

void main() {
  group('GoalPrompts.buildConsultPrompt の今日の日付', () {
    test('今日の日付を渡すと、期限の基準としてプロンプトに入る', () {
      final prompt = GoalPrompts.buildConsultPrompt(
        '依頼人: 5kg減らしたい',
        today: '2026-10-11',
      );
      expect(prompt, contains('【今日の日付】'));
      expect(prompt, contains('2026-10-11'));
      expect(prompt, contains('deadline'));
    });

    test('今日の日付は会話履歴より前に置く', () {
      final prompt = GoalPrompts.buildConsultPrompt(
        '依頼人: 5kg減らしたい',
        today: '2026-10-11',
      );
      expect(
        prompt.indexOf('2026-10-11'),
        lessThan(prompt.indexOf('依頼人: 5kg減らしたい')),
      );
    });

    test('今日の日付が空なら、ブロックごと省く', () {
      final prompt = GoalPrompts.buildConsultPrompt('依頼人: 5kg減らしたい');
      expect(prompt, isNot(contains('【今日の日付】')));
      expect(prompt, contains('依頼人: 5kg減らしたい'));
    });
  });
}
