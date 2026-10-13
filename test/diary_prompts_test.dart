import 'package:flutter_test/flutter_test.dart';
import 'package:nikkinext/models/goal.dart';
import 'package:nikkinext/models/record_field.dart';
import 'package:nikkinext/prompts/diary_prompts.dart';

// 所見・今日のコメント・聴取のプロンプトに、記録が「何の記録か」付きで載ることを検証する。
//
// ここを固める理由:
// 記録に保存されているのは custom_<uuid> / goal_<uuid> という項目 id だけで、
// 名前は記録の型・目標の側にしかない。対応表を渡し忘れても画面はエラーにならず、
// 「所見がカスタム項目を無視している」という静かな抜け方をする。
// 逆に、定義ごと消された項目の値まで拾うと、何の記録か分からない値を AI に渡すことになる。
void main() {
  const goal = Goal(
    id: 'g',
    title: '5kg減らす',
    actions: [GoalAction(id: 'a1', label: 'ジムに行く')],
  );
  final fields = <String, RecordField>{
    kSleepFieldId: const RecordField(
      id: kSleepFieldId,
      label: '睡眠時間',
      kind: FieldKind.numeric,
      unit: '時間',
    ),
    'custom_q1': const RecordField(id: 'custom_q1', label: '心が動く瞬間'),
    'goal_a1': RecordField.fromGoalAction(goal, goal.actions.single),
  };

  // mergeDays の結果と同じ形の1日分。values には現役・削除済みのキーを混ぜてある。
  final days = [
    MapEntry('2026-09-20', <String, dynamic>{
      'diary': '七時間の睡眠で一日が明けた。',
      'values': {
        kSleepFieldId: 7,
        'custom_q1': 'ラジオで昔の曲が流れた',
        'goal_a1': true,
        'custom_deleted': '消した項目の値',
      },
    }),
  ];

  group('buildAnalysisPrompt', () {
    test('項目名付きで記録が載る（目標の項目は目標名も添える）', () {
      final prompt = DiaryPrompts.buildAnalysisPrompt(days, fields: fields);
      expect(prompt, contains('睡眠時間:7時間'));
      expect(prompt, contains('心が動く瞬間:ラジオで昔の曲が流れた'));
      expect(prompt, contains('目標「5kg減らす」の「ジムに行く」:達成'));
      expect(prompt, contains('日記: 七時間の睡眠で一日が明けた。'));
    });

    test('対応表に無い値は渡さない（何の記録か分からないため）', () {
      final prompt = DiaryPrompts.buildAnalysisPrompt(days, fields: fields);
      expect(prompt, isNot(contains('消した項目の値')));
    });

    test('対応表を省いても日記だけで組み立てられる', () {
      final prompt = DiaryPrompts.buildAnalysisPrompt(days);
      expect(prompt, contains('七時間の睡眠で一日が明けた。'));
      expect(prompt, isNot(contains('ラジオで昔の曲が流れた')));
    });
  });

  group('buildDailyCommentPrompt', () {
    test('今日の記録にも直近の記録にも項目名が付く', () {
      final prompt = DiaryPrompts.buildDailyCommentPrompt(
        days.first.value,
        days,
        fields: fields,
      );
      // 今日の記録と比較参考用の直近分で、同じ行が2回出る
      expect('心が動く瞬間:ラジオで昔の曲が流れた'.allMatches(prompt).length, 2);
      expect(prompt, isNot(contains('消した項目の値')));
    });
  });

  group('聴取', () {
    test('話題の候補出しに記録・既に話した出来事を渡す', () {
      final prompt = DiaryPrompts.buildTopicPrompt(
        recordContext: '- 午前にしたこと: 散歩した',
        coveredTopics: const ['カフェで英語で注文した'],
      );
      expect(prompt, contains('散歩した'));
      expect(prompt, contains('【既に話した出来事】'));
      expect(prompt, contains('カフェで英語で注文した'));
    });

    test('記録が無い日はそう伝える', () {
      final prompt = DiaryPrompts.buildTopicPrompt(recordContext: '');
      expect(prompt, contains('まだ記録は無い'));
      expect(prompt, isNot(contains('【既に話した出来事】')));
    });

    test('日記の生成に日々の記録を織り込ませる', () {
      final prompt = DiaryPrompts.buildDiaryPrompt(
        '依頼人: 楽しかった',
        recordContext: '- 睡眠時間: 7時間',
      );
      expect(prompt, contains('【日々の記録'));
      expect(prompt, contains('睡眠時間: 7時間'));
    });

    test('記録が無ければ記録の節を付けない', () {
      final prompt = DiaryPrompts.buildDiaryPrompt('依頼人: 楽しかった');
      expect(prompt, isNot(contains('【日々の記録')));
    });
  });
}
