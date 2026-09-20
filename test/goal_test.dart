import 'package:flutter_test/flutter_test.dart';
import 'package:nikkinext/models/goal.dart';

// 目標（追跡中の事件）の保存モデルと、探偵AIへの差し込み文面を検証する。
//
// ここを固める理由:
// 目標は相談室でAIが組み立てた内容をそのままFirestoreへ書くため、
// 項目の欠損や未知の値（AIが想定外の type を返す、古いドキュメントを読む）で
// ホームや分析室が壊れないことを機械で確かめておきたい。
// また行動項目の回答キー 'goal_<id>' は日々の記録との紐付けそのものなので、
// 形が変わっていないことをテストで固定する。
void main() {
  group('GoalAction', () {
    test('空のマップから読んでもデフォルトで埋まる（項目追加前のドキュメント対策）', () {
      final loaded = GoalAction.fromMap(const {});
      expect(loaded.id, '');
      expect(loaded.label, '');
      expect(loaded.type, GoalActionType.check);
      expect(loaded.unit, '');
      expect(loaded.target, isNull);
    });

    test('未知の type は check に倒す（2択なら記録だけは続けられる）', () {
      expect(goalActionTypeFrom('numeric'), GoalActionType.numeric);
      expect(goalActionTypeFrom('check'), GoalActionType.check);
      expect(goalActionTypeFrom('unknown'), GoalActionType.check);
      expect(goalActionTypeFrom(null), GoalActionType.check);
      expect(goalActionTypeFrom('Numeric'), GoalActionType.check); // 大文字は別物
    });

    test('toMap → fromMap の往復で値が保たれる', () {
      const original = GoalAction(
        id: 'a1',
        label: '体重',
        type: GoalActionType.numeric,
        unit: 'kg',
        target: 62.5,
      );
      final restored = GoalAction.fromMap(original.toMap());
      expect(restored.id, 'a1');
      expect(restored.label, '体重');
      expect(restored.type, GoalActionType.numeric);
      expect(restored.unit, 'kg');
      expect(restored.target, 62.5);
    });

    test('target が int で保存されていても double として読める', () {
      final loaded = GoalAction.fromMap(const {'id': 'a1', 'target': 60});
      expect(loaded.target, 60.0);
    });

    test('回答キーは goal_<id>（日々の記録との紐付けキー）', () {
      const action = GoalAction(id: 'abc-123', label: '体重');
      expect(action.answerKey, 'goal_abc-123');
      expect(action.answerKey.startsWith(kGoalAnswerPrefix), isTrue);
    });

    test('質問文は型と単位で出し分ける', () {
      const check = GoalAction(id: 'a1', label: 'ジムに行く');
      expect(check.questionText(), contains('ジムに行く'));

      const withUnit = GoalAction(
        id: 'a2',
        label: '体重',
        type: GoalActionType.numeric,
        unit: 'kg',
      );
      expect(withUnit.questionText(), contains('kg'));

      const noUnit = GoalAction(
        id: 'a3',
        label: '歩数',
        type: GoalActionType.numeric,
      );
      expect(noUnit.questionText(), contains('数字'));
    });
  });

  group('Goal', () {
    test('何も登録していなければ未設定（isEmpty）', () {
      const defaults = Goal();
      expect(defaults.isEmpty, isTrue);
      expect(defaults.actions, isEmpty);
      expect(defaults.suggestedQuestions, isEmpty);
      expect(Goal.defaults().isEmpty, isTrue);
    });

    test('空白だけのタイトルも未設定として扱う', () {
      expect(const Goal(title: '   ').isEmpty, isTrue);
      expect(const Goal(title: '5kg減らす').isEmpty, isFalse);
    });

    test('空のマップから読んでもデフォルトで埋まる', () {
      final loaded = Goal.fromMap(const {});
      expect(loaded.id, '');
      expect(loaded.title, '');
      expect(loaded.metric, '');
      expect(loaded.deadline, '');
      expect(loaded.actions, isEmpty);
      expect(loaded.suggestedQuestions, isEmpty);
      expect(loaded.createdAt, '');
      expect(loaded.isEmpty, isTrue);
    });

    test('toMap → fromMap の往復で値が保たれる', () {
      const original = Goal(
        id: 'g1',
        title: '3ヶ月で5kg減らす',
        metric: '体重62.0kg以下',
        deadline: '2026-12-31',
        actions: [
          GoalAction(
            id: 'a1',
            label: '体重',
            type: GoalActionType.numeric,
            unit: 'kg',
            target: 62,
          ),
          GoalAction(id: 'a2', label: 'ジムに行く'),
        ],
        suggestedQuestions: ['今日の食事で満足できたのはどれ？'],
        createdAt: '2026-09-19',
      );
      final restored = Goal.fromMap(original.toMap());
      expect(restored.id, 'g1');
      expect(restored.title, '3ヶ月で5kg減らす');
      expect(restored.metric, '体重62.0kg以下');
      expect(restored.deadline, '2026-12-31');
      expect(restored.createdAt, '2026-09-19');
      expect(restored.actions.length, 2);
      expect(restored.actions.first.unit, 'kg');
      expect(restored.actions.last.type, GoalActionType.check);
      expect(restored.suggestedQuestions, ['今日の食事で満足できたのはどれ？']);
    });

    test('copyWith は指定したフィールドだけ差し替える', () {
      const original = Goal(id: 'g1', title: '5kg減らす', metric: '62kg以下');
      final next = original.copyWith(suggestedQuestions: const ['Q1']);
      expect(next.id, 'g1');
      expect(next.title, '5kg減らす');
      expect(next.metric, '62kg以下');
      expect(next.suggestedQuestions, ['Q1']);
    });

    test('回答キーからラベルを引ける（保存された回答を読み戻すため）', () {
      const goal = Goal(
        title: '5kg減らす',
        actions: [
          GoalAction(id: 'a1', label: '体重', type: GoalActionType.numeric),
          GoalAction(id: 'a2', label: 'ジムに行く'),
        ],
      );
      expect(goal.answerLabels(), {'goal_a1': '体重', 'goal_a2': 'ジムに行く'});
      expect(const Goal().answerLabels(), isEmpty);
    });

    test('数値項目とチェック項目を型で振り分けられる', () {
      const goal = Goal(
        title: '5kg減らす',
        actions: [
          GoalAction(id: 'a1', label: '体重', type: GoalActionType.numeric),
          GoalAction(id: 'a2', label: 'ジム'),
          GoalAction(id: 'a3', label: '歩数', type: GoalActionType.numeric),
        ],
      );
      expect(goal.numericActions.map((a) => a.id), ['a1', 'a3']);
      expect(goal.checkActions.map((a) => a.id), ['a2']);
    });
  });

  group('Goal.promptSummary', () {
    test('未設定なら空文字（AIへ何も渡さない）', () {
      expect(const Goal().promptSummary(), '');
      expect(const Goal(title: '  ').promptSummary(), '');
    });

    test('タイトルだけでも要約になる（期限・項目が無くても成立する）', () {
      const goal = Goal(title: '5kg減らす');
      final summary = goal.promptSummary();
      expect(summary, contains('5kg減らす'));
      expect(summary, isNot(contains('期限')));
      expect(summary, isNot(contains('日々追っている項目')));
    });

    test('登録した内容が要約に入る', () {
      const goal = Goal(
        title: '3ヶ月で5kg減らす',
        metric: '体重62.0kg以下',
        deadline: '2026-12-31',
        actions: [
          GoalAction(
            id: 'a1',
            label: '体重',
            type: GoalActionType.numeric,
            unit: 'kg',
          ),
          GoalAction(id: 'a2', label: 'ジムに行く'),
        ],
      );
      final summary = goal.promptSummary();
      expect(summary, contains('3ヶ月で5kg減らす'));
      expect(summary, contains('体重62.0kg以下'));
      expect(summary, contains('2026-12-31'));
      expect(summary, contains('体重'));
      expect(summary, contains('ジムに行く'));
    });
  });

  // AI の出力はスキーマを指定していても保証されない。
  // 崩れた応答でアプリが落ちたり、紐付けの壊れた項目が保存されたりしないことを固める。
  group('Goal.fromAiMap', () {
    test('空のマップでも落ちず、未確定の目標になる', () {
      final goal = Goal.fromAiMap(const {}, createdAt: '2026-09-19');
      expect(goal.title, '');
      expect(goal.isEmpty, isTrue);
      expect(goal.actions, isEmpty);
      expect(goal.suggestedQuestions, isEmpty);
      expect(goal.createdAt, '2026-09-19');
      expect(goal.id, isNotEmpty); // id は必ずクライアント側で発行する
    });

    test('行動項目に id を振る。id は項目ごとに異なる', () {
      final goal = Goal.fromAiMap(const {
        'title': '5kg減らす',
        'actions': [
          {'label': '体重', 'type': 'numeric', 'unit': 'kg'},
          {'label': 'ジムに行く', 'type': 'check'},
        ],
      }, createdAt: '2026-09-19');
      expect(goal.actions.length, 2);
      expect(goal.actions[0].id, isNotEmpty);
      expect(goal.actions[1].id, isNotEmpty);
      expect(goal.actions[0].id, isNot(goal.actions[1].id));
      expect(goal.actions[0].answerKey, startsWith(kGoalAnswerPrefix));
    });

    test('actions が壊れていても空リストとして扱う', () {
      expect(
        Goal.fromAiMap(const {
          'actions': 'たくさん',
        }, createdAt: '2026-09-19').actions,
        isEmpty,
      );
      expect(
        Goal.fromAiMap(const {
          'actions': ['体重', 42],
        }, createdAt: '2026-09-19').actions,
        isEmpty,
      );
    });

    test('ラベルの無い行動項目は捨てる（質問文にできないため）', () {
      final goal = Goal.fromAiMap(const {
        'actions': [
          {'label': '', 'type': 'numeric'},
          {'label': '   ', 'type': 'check'},
          {'label': '体重', 'type': 'numeric'},
        ],
      }, createdAt: '2026-09-19');
      expect(goal.actions.map((a) => a.label), ['体重']);
    });

    test('未知の type は check に倒す', () {
      final goal = Goal.fromAiMap(const {
        'actions': [
          {'label': 'A', 'type': 'slider'},
          {'label': 'B'},
        ],
      }, createdAt: '2026-09-19');
      expect(goal.actions.every((a) => a.type == GoalActionType.check), isTrue);
    });

    test('target が文字列で返ってきても数値として読む', () {
      final goal = Goal.fromAiMap(const {
        'actions': [
          {'label': '体重', 'type': 'numeric', 'target': '62.5'},
          {'label': '歩数', 'type': 'numeric', 'target': 8000},
          {'label': '気分', 'type': 'numeric', 'target': 'たくさん'},
        ],
      }, createdAt: '2026-09-19');
      expect(goal.actions[0].target, 62.5);
      expect(goal.actions[1].target, 8000.0);
      expect(goal.actions[2].target, isNull);
    });

    test('行動項目が多すぎるときは上限まで切る（毎日答える数を増やしすぎない）', () {
      final goal = Goal.fromAiMap(const {
        'actions': [
          {'label': 'A'},
          {'label': 'B'},
          {'label': 'C'},
          {'label': 'D'},
          {'label': 'E'},
        ],
      }, createdAt: '2026-09-19');
      expect(goal.actions.length, kMaxGoalActions);
      expect(goal.actions.map((a) => a.label), ['A', 'B', 'C']);
    });

    test('独自質問は空文字を除き、上限まで切る', () {
      final goal = Goal.fromAiMap(const {
        'questions': ['Q1', '', '   ', 'Q2', 'Q3', 'Q4', 'Q5', 'Q6', 'Q7'],
      }, createdAt: '2026-09-19');
      expect(goal.suggestedQuestions.length, kMaxGoalQuestions);
      expect(goal.suggestedQuestions.first, 'Q1');
      expect(goal.suggestedQuestions.contains(''), isFalse);
    });

    test('前後の空白を落として取り込む', () {
      final goal = Goal.fromAiMap(const {
        'title': '  5kg減らす  ',
        'metric': ' 62kg以下 ',
        'deadline': ' 2026-12-31 ',
      }, createdAt: '2026-09-19');
      expect(goal.title, '5kg減らす');
      expect(goal.metric, '62kg以下');
      expect(goal.deadline, '2026-12-31');
    });
  });

  // ── 複数目標の上限と枠 ──────────────────────────────────────
  //
  // 毎日の尋問に出る項目は全目標の合計で数える。目標ごとの上限だけだと
  // 3目標で9問になり、記録が作業になってしまう。枠の数え方はUIから見えないので
  // ここで固めておく。
  group('行動項目の枠', () {
    Goal goalWith(String id, int actionCount) => Goal(
      id: id,
      title: '目標$id',
      actions: [
        for (var i = 0; i < actionCount; i++)
          GoalAction(id: '$id-$i', label: '項目$i'),
      ],
    );

    test('totalGoalActions は全目標の行動項目を足す', () {
      expect(totalGoalActions(const []), 0);
      expect(
        totalGoalActions([
          goalWith('a', 2),
          goalWith('b', 1),
          goalWith('c', 0),
        ]),
        3,
      );
    });

    test('remainingActionSlots は合計から引いた残り', () {
      expect(remainingActionSlots(const []), kMaxTotalGoalActions);
      expect(remainingActionSlots([goalWith('a', 2)]), 3);
      expect(remainingActionSlots([goalWith('a', 3), goalWith('b', 2)]), 0);
    });

    test('remainingActionSlots は枠を超えても0未満にならない', () {
      expect(remainingActionSlots([goalWith('a', 3), goalWith('b', 3)]), 0);
    });

    test('excludingGoalId に渡した目標の項目は数えない（見直しで枠が戻る）', () {
      final goals = [goalWith('a', 3), goalWith('b', 2)];
      expect(remainingActionSlots(goals), 0);
      expect(remainingActionSlots(goals, excludingGoalId: 'a'), 3);
    });

    test('excludingGoalId が空文字なら除外扱いしない（id無しの古いデータ対策）', () {
      final goals = [Goal(title: '無ID', actions: goalWith('a', 2).actions)];
      expect(remainingActionSlots(goals, excludingGoalId: ''), 3);
    });

    test('selectableActionSlots は1目標あたりの上限で頭打ちになる', () {
      expect(selectableActionSlots(const []), kMaxGoalActions);
      expect(selectableActionSlots([goalWith('a', 1)]), kMaxGoalActions);
      expect(selectableActionSlots([goalWith('a', 4)]), 1);
      expect(selectableActionSlots([goalWith('a', 5)]), 0);
    });
  });

  // ── 並び順 ──────────────────────────────────────────────────
  group('Goal.byNewest', () {
    test('着手日の新しい順に並ぶ', () {
      final goals = [
        const Goal(id: 'a', title: '古', createdAt: '2026-01-01'),
        const Goal(id: 'b', title: '新', createdAt: '2026-09-01'),
        const Goal(id: 'c', title: '中', createdAt: '2026-05-01'),
      ]..sort(Goal.byNewest);
      expect(goals.map((g) => g.id), ['b', 'c', 'a']);
    });

    test('着手日が空のものは末尾へ回る', () {
      final goals = [
        const Goal(id: 'a', title: '不明'),
        const Goal(id: 'b', title: '既知', createdAt: '2026-01-01'),
      ]..sort(Goal.byNewest);
      expect(goals.map((g) => g.id), ['b', 'a']);
    });

    test('同じ着手日は id で決まり、並べ直しても順序が変わらない', () {
      final goals = [
        const Goal(id: 'z', title: 'Z', createdAt: '2026-09-01'),
        const Goal(id: 'a', title: 'A', createdAt: '2026-09-01'),
      ]..sort(Goal.byNewest);
      expect(goals.map((g) => g.id), ['a', 'z']);
      goals.sort(Goal.byNewest);
      expect(goals.map((g) => g.id), ['a', 'z']);
    });
  });

  // ── AIへ渡す1行要約 ─────────────────────────────────────────
  group('promptHeadline', () {
    test('未設定なら空文字（セクションごと省ける）', () {
      expect(Goal.defaults().promptHeadline(), '');
    });

    test('タイトルだけでも1行になる', () {
      expect(const Goal(title: '5kg減らす').promptHeadline(), '- 5kg減らす');
    });

    test('期限と項目名が括弧に入る', () {
      const goal = Goal(
        title: '5kg減らす',
        deadline: '2026-12-31',
        actions: [
          GoalAction(id: '1', label: '体重', type: GoalActionType.numeric),
          GoalAction(id: '2', label: 'ジムに行く'),
        ],
      );
      expect(goal.promptHeadline(), '- 5kg減らす（期限 2026-12-31 / 体重・ジムに行く）');
    });
  });

  // ── 追跡を終えた理由 ────────────────────────────────────────
  group('GoalOutcome', () {
    test('保存文字列と往復する', () {
      expect(
        goalOutcomeFrom(goalOutcomeTo(GoalOutcome.solved)),
        GoalOutcome.solved,
      );
      expect(
        goalOutcomeFrom(goalOutcomeTo(GoalOutcome.abandoned)),
        GoalOutcome.abandoned,
      );
    });

    test('未知の値と欠損は null（断念と誤って刻印しない）', () {
      expect(goalOutcomeFrom(null), isNull);
      expect(goalOutcomeFrom(''), isNull);
      expect(goalOutcomeFrom('Solved'), isNull);
      expect(goalOutcomeFrom('archived'), isNull);
    });
  });

  // ── AI応答の件数制限 ────────────────────────────────────────
  group('fromAiMap の maxActions', () {
    Map<String, dynamic> aiMapWith(int count) => {
      'title': '5kg減らす',
      'actions': [
        for (var i = 0; i < count; i++) {'label': '項目$i', 'type': 'check'},
      ],
    };

    test('残り枠の件数で切り詰める', () {
      final goal = Goal.fromAiMap(
        aiMapWith(3),
        createdAt: '2026-09-19',
        maxActions: 2,
      );
      expect(goal.actions.length, 2);
      expect(goal.actions.map((a) => a.label), ['項目0', '項目1']);
    });

    test('残り枠が0なら行動項目を1件も取り込まない', () {
      final goal = Goal.fromAiMap(
        aiMapWith(3),
        createdAt: '2026-09-19',
        maxActions: 0,
      );
      expect(goal.actions, isEmpty);
      expect(goal.title, '5kg減らす'); // 方針だけの目標は成立する
    });

    test('既定は1目標あたりの上限', () {
      final goal = Goal.fromAiMap(aiMapWith(5), createdAt: '2026-09-19');
      expect(goal.actions.length, kMaxGoalActions);
    });
  });

  // ── 旧スキーマからの移行 ────────────────────────────────────
  //
  // goals/current の1件だけを読んでいた頃のドキュメントが開発機に残っている。
  // 読んだときに振り分けて goals/{goalId} へ移すので、その振り分けを固める。
  group('partitionGoalDocs', () {
    MapEntry<String, Map<String, dynamic>> doc(
      String id,
      Map<String, dynamic> data,
    ) => MapEntry(id, data);

    test('current は legacy 側へ、それ以外は goals へ振り分ける', () {
      final result = partitionGoalDocs([
        doc('current', {'id': 'old', 'title': '旧目標'}),
        doc('abc', {'id': 'abc', 'title': '新目標'}),
      ]);
      expect(result.legacy?.title, '旧目標');
      expect(result.goals.map((g) => g.id), ['abc']);
    });

    test('current が id を持たなければ発行された id が入る', () {
      final result = partitionGoalDocs([
        doc('current', {'title': '旧目標'}),
      ], newId: () => 'issued-id');
      expect(result.legacy?.id, 'issued-id');
    });

    test('id の欠けた通常ドキュメントはドキュメントIDで埋まる', () {
      final result = partitionGoalDocs([
        doc('doc-1', {'title': '目標'}),
      ]);
      expect(result.goals.single.id, 'doc-1');
    });

    test('タイトルの無いドキュメントは捨てる（空の枠を作らない）', () {
      final result = partitionGoalDocs([
        doc('empty', {'id': 'empty'}),
        doc('blank', {'id': 'blank', 'title': '   '}),
        doc('ok', {'id': 'ok', 'title': '目標'}),
      ]);
      expect(result.goals.map((g) => g.id), ['ok']);
      expect(result.legacy, isNull);
    });

    test('旧ドキュメントが無ければ legacy は null', () {
      final result = partitionGoalDocs([
        doc('a', {'id': 'a', 'title': '目標'}),
      ]);
      expect(result.legacy, isNull);
      expect(result.goals.length, 1);
    });

    test('何も無ければ空で返る', () {
      final result = partitionGoalDocs(const []);
      expect(result.goals, isEmpty);
      expect(result.legacy, isNull);
    });
  });

  // ── 見直し時の id 引き継ぎ ──────────────────────────────────
  group('carryOverActionIds', () {
    const previous = Goal(
      id: 'g1',
      title: '5kg減らす',
      actions: [
        GoalAction(id: 'keep-1', label: '体重', type: GoalActionType.numeric),
        GoalAction(id: 'keep-2', label: 'ジムに行く'),
      ],
    );

    test('ラベルと型が一致する項目は元の id を引き継ぐ', () {
      const draft = Goal(
        id: 'new',
        title: '5kg減らす',
        actions: [
          GoalAction(id: 'fresh-1', label: '体重', type: GoalActionType.numeric),
        ],
      );
      final carried = carryOverActionIds(draft, previous);
      expect(carried.actions.single.id, 'keep-1');
      expect(carried.actions.single.answerKey, 'goal_keep-1');
    });

    test('ラベルが同じでも型が違えば新しい id のまま', () {
      const draft = Goal(
        id: 'new',
        title: '5kg減らす',
        actions: [GoalAction(id: 'fresh-1', label: '体重')], // check に変わった
      );
      final carried = carryOverActionIds(draft, previous);
      expect(carried.actions.single.id, 'fresh-1');
    });

    test('同じラベルが2件あっても id を二重に配らない', () {
      const twice = Goal(
        id: 'g1',
        title: '目標',
        actions: [
          GoalAction(id: 'keep-1', label: '散歩'),
          GoalAction(id: 'keep-2', label: '散歩'),
        ],
      );
      const draft = Goal(
        id: 'new',
        title: '目標',
        actions: [
          GoalAction(id: 'fresh-1', label: '散歩'),
          GoalAction(id: 'fresh-2', label: '散歩'),
          GoalAction(id: 'fresh-3', label: '散歩'),
        ],
      );
      final carried = carryOverActionIds(draft, twice);
      expect(carried.actions.map((a) => a.id), ['keep-1', 'keep-2', 'fresh-3']);
    });

    test('見直す前の目標が無ければ素通り（新規作成）', () {
      const draft = Goal(
        id: 'new',
        title: '目標',
        actions: [GoalAction(id: 'fresh-1', label: '体重')],
      );
      expect(carryOverActionIds(draft, null).actions.single.id, 'fresh-1');
    });
  });

  // ── 解決済みの並び順 ────────────────────────────────────────
  group('ArchivedGoal.byNewest', () {
    test('退避が新しい順に並び、日時の無いものは末尾へ回る', () {
      final list = [
        ArchivedGoal(
          goal: const Goal(id: 'none', title: '日時なし'),
          archivedAt: null,
        ),
        ArchivedGoal(
          goal: const Goal(id: 'old', title: '古'),
          archivedAt: DateTime.utc(2026, 1, 1),
        ),
        ArchivedGoal(
          goal: const Goal(id: 'new', title: '新'),
          archivedAt: DateTime.utc(2026, 9, 1),
        ),
      ]..sort(ArchivedGoal.byNewest);
      expect(list.map((a) => a.goal.id), ['new', 'old', 'none']);
    });
  });
}
