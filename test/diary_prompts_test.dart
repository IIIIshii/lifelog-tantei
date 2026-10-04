import 'package:flutter_test/flutter_test.dart';
import 'package:nikkinext/prompts/diary_prompts.dart';

// 所見・今日のコメントのプロンプトに、カスタム質問と目標の回答が
// 「何を尋ねた答えか」付きで載ることを検証する。
//
// ここを固める理由:
// エントリに保存されているのは custom_<uuid> / goal_<uuid> という参照キーだけで、
// 質問文は設定・目標の側にしかない。対応表を渡し忘れても画面はエラーにならず、
// 「所見がカスタム質問を無視している」という静かな抜け方をする（実際そうなっていた）。
// 逆に、消された質問の回答まで拾うと、何への答えか分からない値を AI に渡すことになる。
void main() {
  // 1日分のエントリ。answers には現役・削除済み・旧形式のキーを混ぜてある。
  final entries = [
    MapEntry('2026-09-20', <String, dynamic>{
      'diary': '七時間の睡眠で一日が明けた。',
      'answers': {
        'food': 'カフェのパスタ',
        'exercise': 'した',
        'custom_q1': 'ラジオで昔の曲が流れた',
        'goal_a1': '達成',
        'custom_deleted': '消した質問への回答',
        'custom_0': '安定ID導入前の回答',
      },
      'numericAnswers': {'sleep': 7.0},
    }),
  ];

  const labels = {'custom_q1': '心が動く瞬間はあった？', 'goal_a1': '目標「5kg減らす」の「ジムに行く」'};

  group('buildAnalysisPrompt', () {
    test('対応表を渡すと質問文付きで回答が載る', () {
      final prompt = DiaryPrompts.buildAnalysisPrompt(
        entries,
        answerLabels: labels,
      );
      expect(prompt, contains('心が動く瞬間はあった？:ラジオで昔の曲が流れた'));
      expect(prompt, contains('目標「5kg減らす」の「ジムに行く」:達成'));
      // 固定項目はこれまでどおり
      expect(prompt, contains('睡眠7.0h'));
      expect(prompt, contains('食事:カフェのパスタ'));
    });

    test('対応表に無い回答は渡さない（何への答えか分からないため）', () {
      final prompt = DiaryPrompts.buildAnalysisPrompt(
        entries,
        answerLabels: labels,
      );
      expect(prompt, isNot(contains('消した質問への回答')));
      expect(prompt, isNot(contains('安定ID導入前の回答')));
    });

    test('対応表を省いても固定項目だけで組み立てられる', () {
      final prompt = DiaryPrompts.buildAnalysisPrompt(entries);
      expect(prompt, contains('食事:カフェのパスタ'));
      expect(prompt, isNot(contains('ラジオで昔の曲が流れた')));
    });
  });

  group('buildDailyCommentPrompt', () {
    test('今日の回答にも直近の回答にも質問文が付く', () {
      final prompt = DiaryPrompts.buildDailyCommentPrompt(
        entries.first.value,
        entries,
        answerLabels: labels,
      );
      // 今日の記録と比較参考用の直近分で、同じ行が2回出る
      expect('心が動く瞬間はあった？:ラジオで昔の曲が流れた'.allMatches(prompt).length, 2);
      expect(prompt, isNot(contains('消した質問への回答')));
    });
  });
}
