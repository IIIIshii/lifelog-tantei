import 'package:flutter_test/flutter_test.dart';
import 'package:nikkinext/core/goal_digest.dart';
import 'package:nikkinext/models/goal.dart';
import 'package:nikkinext/prompts/diary_prompts.dart';
import 'package:nikkinext/prompts/goal_prompts.dart';

// 目標の続き具合を AI に渡す文と、それを各プロンプトに差し込む部分を検証する。
//
// 続き具合は「答えた日だけを母数にする」「期間の外は数えない」といった、
// 取り違えても画面上は正常に見える数え方の上に成り立っている。ここで固める。
void main() {
  const gym = GoalAction(id: 'gym', label: 'ジムに行く');
  const weight = GoalAction(
    id: 'weight',
    label: '体重',
    type: GoalActionType.numeric,
    unit: 'kg',
  );
  const goal = Goal(
    id: 'g1',
    title: '3ヶ月で5kg減らす',
    createdAt: '2026-10-01',
    actions: [gym, weight],
  );
  final today = DateTime(2026, 10, 14);

  MapEntry<String, Map<String, dynamic>> record(
    String date,
    Map<String, dynamic> values,
  ) => MapEntry(date, {'values': values});

  group('activeGoalsDigest', () {
    test('チェック型は、答えた日を母数に、達成した日を数える', () {
      final digest = activeGoalsDigest(
        [goal],
        [
          record('2026-10-12', {'goal_gym': true}),
          record('2026-10-13', {'goal_gym': false}),
          record('2026-10-14', {'goal_gym': true}),
        ],
        today,
      );
      expect(digest, contains('目標「3ヶ月で5kg減らす」（着手から13日）'));
      expect(digest, contains('「ジムに行く」: 直近14日で記録した3日のうち、達成2日'));
    });

    test('答えなかった日は母数に入れない（未記入と未達は違う）', () {
      final digest = activeGoalsDigest(
        [goal],
        [
          record('2026-10-12', {'goal_gym': true}),
          record('2026-10-13', {'sleep': 7}), // 目標の項目は未記入
        ],
        today,
      );
      expect(digest, contains('記録した1日のうち、達成1日'));
    });

    test('数値型は、期間内の最新の値を単位つきで出す', () {
      final digest = activeGoalsDigest(
        [goal],
        [
          record('2026-10-10', {'goal_weight': 63.0}),
          record('2026-10-13', {'goal_weight': 62.5}),
        ],
        today,
      );
      expect(digest, contains('「体重」: 直近の値 62.5kg'));
    });

    test('期間（直近14日）の外の記録は数えない', () {
      final digest = activeGoalsDigest(
        [goal],
        [
          record('2026-09-30', {'goal_gym': true}), // 15日前
          record('2026-10-14', {'goal_gym': false}),
        ],
        today,
      );
      expect(digest, contains('記録した1日のうち、達成0日'));
    });

    test('月をまたいでも、期間の端（14日前の当日）は数える', () {
      final digest = activeGoalsDigest(
        [goal],
        [
          record('2026-10-01', {'goal_gym': true}),
        ], // 今日から13日前＝期間の最初の日
        today,
      );
      expect(digest, contains('記録した1日のうち、達成1日'));
    });

    test('記録が1日も無い項目は、「記録なし」と書く（0日達成と区別する）', () {
      final digest = activeGoalsDigest([goal], const [], today);
      expect(digest, contains('「ジムに行く」: 直近14日は記録なし'));
      expect(digest, contains('「体重」: 直近14日は記録なし'));
    });

    test('段階を持つ目標は、今の段階も添える', () {
      const stepped = Goal(
        id: 'g2',
        title: '英語を話せるようになる',
        createdAt: '2026-10-01',
        steps: [GoalStep(id: 's1', title: 'まず毎日10分', deadline: '2026-11-15')],
      );
      final digest = activeGoalsDigest([stepped], const [], today);
      expect(digest, contains('段階 1/1：まず毎日10分（期限 2026-11-15）'));
    });

    test('目標が無い・題が空の目標しかないときは空文字', () {
      expect(activeGoalsDigest(const [], const [], today), '');
      expect(activeGoalsDigest([const Goal()], const [], today), '');
    });

    test('同じ入力なら同じ文になる', () {
      final records = [
        record('2026-10-12', {'goal_gym': true}),
      ];
      expect(
        activeGoalsDigest([goal], records, today),
        activeGoalsDigest([goal], records, today),
      );
    });
  });

  group('closedGoalsDigest', () {
    const solved = Goal(
      id: 'a',
      title: '本を読み切る',
      createdAt: '2026-08-01',
      status: GoalStatus.solved,
      closedAt: '2026-09-01',
    );
    const abandoned = Goal(
      id: 'b',
      title: '毎朝走る',
      createdAt: '2026-09-01',
      status: GoalStatus.abandoned,
      closedAt: '2026-09-20',
    );

    test('新しく終えたものから並べ、終え方と期間を添える', () {
      final digest = closedGoalsDigest([solved, abandoned]);
      expect(digest.split('\n'), [
        '- 目標「毎朝走る」: 断念した（2026-09-01〜2026-09-20）',
        '- 目標「本を読み切る」: 解決した（2026-08-01〜2026-09-01）',
      ]);
    });

    test('結末が記録されていない古いデータは、推測せずそう書く', () {
      const legacy = Goal(id: 'c', title: '古い目標', status: GoalStatus.closed);
      final digest = closedGoalsDigest([legacy]);
      expect(digest, '- 目標「古い目標」: 追跡を終えた（結末は記録されていない）');
    });

    test('件数は上限で切る', () {
      final many = [
        for (var i = 0; i < 8; i++)
          Goal(
            id: 'g$i',
            title: '目標$i',
            status: GoalStatus.solved,
            closedAt: '2026-09-0${i + 1}',
          ),
      ];
      expect(
        closedGoalsDigest(many).split('\n').length,
        kMaxClosedGoalsInDigest,
      );
    });

    test('終えた目標が無ければ空文字', () {
      expect(closedGoalsDigest(const []), '');
    });
  });

  group('プロンプトへの差し込み', () {
    test('最初の質問に、目標の続き具合と「責めない」注意が付く', () {
      final prompt = DiaryPrompts.buildTopicQuestionPrompt(
        topic: '仕事',
        recordContext: '- 睡眠時間: 7時間',
        goalContext: '- 目標「走る」',
      );
      expect(prompt, contains('【追っている目標と続き具合】'));
      expect(prompt, contains('責めたり、急かしたりしない'));
    });

    test('目標が無ければ、最初の質問は今までと同じ形のまま', () {
      final prompt = DiaryPrompts.buildTopicQuestionPrompt(
        topic: '仕事',
        recordContext: '',
      );
      expect(prompt, '依頼人が話したい出来事：仕事');
    });

    test('深掘りには、今日の記録と目標の続き具合の両方が付く', () {
      final context = DiaryPrompts.followUpContext(
        recordContext: '- 睡眠時間: 7時間',
        goalContext: '- 目標「走る」',
      );
      expect(context, contains('【今日の記録】\n- 睡眠時間: 7時間'));
      expect(context, contains('【追っている目標と続き具合】'));
    });

    test('深掘りの参考情報は、どちらも無ければ空文字', () {
      expect(DiaryPrompts.followUpContext(), '');
    });

    test('相談室に、続き具合と終えた事件が、会話の前に付く', () {
      final prompt = GoalPrompts.buildConsultPrompt(
        '依頼人: 走りたい',
        progressDigest: '- 目標「走る」',
        pastGoalsDigest: '- 目標「毎朝走る」: 断念した',
      );
      expect(prompt, contains('【追っている事件の続き具合】'));
      expect(prompt, contains('【これまでに終えた事件】'));
      expect(prompt, contains('なぜ終えたかは分かりません'));
      expect(
        prompt.indexOf('【これまでに終えた事件】'),
        lessThan(prompt.indexOf('依頼人: 走りたい')),
      );
    });

    test('相談室で材料が無ければ、これまでと同じ形のまま', () {
      final prompt = GoalPrompts.buildConsultPrompt('依頼人: 走りたい');
      expect(prompt, isNot(contains('続き具合')));
      expect(prompt, isNot(contains('終えた事件')));
    });
  });
}
