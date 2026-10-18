import 'package:flutter_test/flutter_test.dart';
import 'package:nikkinext/core/daily_record.dart';
import 'package:nikkinext/models/goal.dart';
import 'package:nikkinext/models/record_field.dart';

// 日々の記録（records/{date}）を扱う純関数を検証する。
//
// ここを固める理由:
// 「未記入」と「0 や いいえ を記録した」の取り違え、曜日での絞り込み、
// 目標の項目の混ぜ方、日記に使わない項目の除外は、間違えても画面上は
// 正常に見える（値が静かに消える・余計な事実が日記に混ざる）種類の誤りなので、
// 機械で確かめておきたい。
Map<String, dynamic> _record(Map<String, Object?> values) => {
  'values': values,
};

const _sleep = RecordField(
  id: kSleepFieldId,
  label: '睡眠時間',
  kind: FieldKind.numeric,
  unit: '時間',
);
const _exercise = RecordField(
  id: kExerciseFieldId,
  label: '運動した',
  kind: FieldKind.yesNo,
);
const _mood = RecordField(
  id: kMoodFieldId,
  label: '今日の気分',
  kind: FieldKind.choice,
  choices: kMoodChoices,
);
const _morning = RecordField(id: kMorningFieldId, label: '午前にしたこと');
const _weight = RecordField(
  id: 'custom_w',
  label: '体重',
  kind: FieldKind.numeric,
  unit: 'kg',
  useInDiary: false,
);

void main() {
  group('値の取り出し', () {
    test('0 と いいえ は「記録した」として扱う（未記入と区別する）', () {
      final record = _record({'n': 0, 'b': false});
      expect(numberOf(record, 'n'), 0.0);
      expect(flagOf(record, 'b'), isFalse);
      expect(hasAnyValue(record), isTrue);
    });

    test('空文字・空白だけの文字列は未記入', () {
      final record = _record({'t': '  '});
      expect(valueOf(record, 't'), isNull);
      expect(hasAnyValue(record), isFalse);
    });

    test('int で保存されていても double で返す', () {
      expect(numberOf(_record({'n': 8000}), 'n'), 8000.0);
    });

    test('型の違う値は取り出さない', () {
      final record = _record({'n': '7', 'b': 'はい'});
      expect(numberOf(record, 'n'), isNull);
      expect(flagOf(record, 'b'), isNull);
    });

    test('ドキュメントが無い日・values の無い日は null', () {
      expect(valueOf(null, 'x'), isNull);
      expect(valueOf(const {}, 'x'), isNull);
      expect(hasAnyValue(null), isFalse);
    });
  });

  group('normalizeInput', () {
    test('数値欄は全角や単位付きでも数値にする', () {
      expect(normalizeInput(_sleep, '７.５時間'), 7.5);
      expect(normalizeInput(_sleep, '62kg'), 62.0);
      expect(normalizeInput(_sleep, 6), 6);
    });

    test('数字の無い数値欄・空欄は未記入（null）に戻す', () {
      expect(normalizeInput(_sleep, 'たくさん'), isNull);
      expect(normalizeInput(_sleep, ''), isNull);
    });

    test('選択肢に無い値は受け付けない', () {
      expect(normalizeInput(_mood, '良い'), '良い');
      expect(normalizeInput(_mood, '最高'), isNull);
    });

    test('はい／いいえは bool だけ', () {
      expect(normalizeInput(_exercise, true), isTrue);
      expect(normalizeInput(_exercise, 'はい'), isNull);
    });

    test('テキストは前後の空白を落とし、空なら未記入', () {
      expect(normalizeInput(_morning, '  散歩した \n'), '散歩した');
      expect(normalizeInput(_morning, '   '), isNull);
    });
  });

  group('formatValue', () {
    test('数値は単位付き、整数に .0 を付けない', () {
      expect(formatValue(_sleep, 7.0), '7時間');
      expect(formatValue(_sleep, 7.5), '7.5時間');
    });

    test('はい／いいえ。目標の項目は達成／未達で出す', () {
      expect(formatValue(_exercise, true), 'はい');
      expect(formatValue(_exercise, false), 'いいえ');
      const goal = Goal(id: 'g', title: '鍛える');
      const action = GoalAction(id: 'j', label: 'ジムに行く');
      final goalField = RecordField.fromGoalAction(goal, action);
      expect(formatValue(goalField, true), kGoalDone);
      expect(formatValue(goalField, false), kGoalNotDone);
    });

    test('未記入は null', () {
      expect(formatValue(_sleep, null), isNull);
      expect(formatValue(_morning, ''), isNull);
    });
  });

  group('fieldsForDay', () {
    // 2026-10-05 は月曜日
    final monday = DateTime(2026, 10, 5);

    test('使っている項目のうち、その曜日に出すものだけ', () {
      const weekendOnly = RecordField(id: 'w', label: '週末', weekdays: [6, 7]);
      const unused = RecordField(id: 'u', label: '使わない', active: false);
      final fields = fieldsForDay(
        [_sleep, weekendOnly, unused],
        const [],
        monday,
      );
      expect(fields.map((f) => f.id), [kSleepFieldId]);
    });

    test('生活の記録の後ろに、追跡中の目標の項目が続く', () {
      const goal = Goal(
        id: 'g',
        title: '鍛える',
        createdAt: '2026-10-01',
        actions: [GoalAction(id: 'j', label: 'ジムに行く')],
      );
      final fields = fieldsForDay([_sleep], const [goal], monday);
      expect(fields.map((f) => f.id), [kSleepFieldId, 'goal_j']);
      expect(fields.last.goalId, 'g');
    });

    test('着手前の日には目標の項目を出さない', () {
      const goal = Goal(
        id: 'g',
        title: '鍛える',
        createdAt: '2026-10-10',
        actions: [GoalAction(id: 'j', label: 'ジムに行く')],
      );
      expect(fieldsForDay(const [], const [goal], monday), isEmpty);
    });

    test('目標の項目は全目標で上限まで', () {
      final goals = [
        for (var g = 0; g < 3; g++)
          Goal(
            id: 'g$g',
            title: '目標$g',
            actions: [
              for (var a = 0; a < 3; a++)
                GoalAction(id: 'a$g$a', label: '項目$a'),
            ],
          ),
      ];
      expect(
        fieldsForDay(const [], goals, monday).length,
        kMaxTotalGoalActions,
      );
    });
  });

  group('recordProgress', () {
    test('記入した項目と全項目を数える', () {
      final progress = recordProgress(
        [_sleep, _exercise, _morning],
        _record({kSleepFieldId: 7, kExerciseFieldId: false, 'other': 'x'}),
      );
      expect(progress.filled, 2);
      expect(progress.total, 3);
    });

    test('記録が無い日は 0 件', () {
      final progress = recordProgress([_sleep], null);
      expect(progress, (filled: 0, total: 1));
    });
  });

  group('recordSummary', () {
    final record = _record({
      kSleepFieldId: 7,
      'custom_w': 62.5,
      kMorningFieldId: '散歩した',
    });

    test('記入済みの項目を「- ラベル: 値」で並べる', () {
      final summary = recordSummary([_sleep, _weight, _morning], record);
      expect(summary, contains('- 睡眠時間: 7時間'));
      expect(summary, contains('- 体重: 62.5kg'));
      expect(summary, contains('- 午前にしたこと: 散歩した'));
    });

    test('diaryOnly では日記に使わない項目を外す', () {
      final summary = recordSummary(
        [_sleep, _weight, _morning],
        record,
        diaryOnly: true,
      );
      expect(summary, isNot(contains('体重')));
      expect(summary, contains('睡眠時間'));
    });

    test('記録が無ければ空文字', () {
      expect(recordSummary([_sleep], null), isEmpty);
    });
  });

  group('topicHintsFromRecord', () {
    test('日記に使うテキスト項目の内容を見出しにする', () {
      const secret = RecordField(id: 's', label: '秘密', useInDiary: false);
      final hints = topicHintsFromRecord(
        [_sleep, _morning, secret],
        _record({kMorningFieldId: '散歩した', 's': '言わない', kSleepFieldId: 7}),
      );
      expect(hints, ['散歩した']);
    });

    test('長い記述は切り詰める', () {
      final hints = topicHintsFromRecord(
        [_morning],
        _record({kMorningFieldId: 'あ' * 30}),
        maxLength: 10,
      );
      expect(hints.single, '${'あ' * 10}…');
    });
  });

  group('mergeDays / recordedDates', () {
    final records = [
      MapEntry('2026-10-01', _record({kSleepFieldId: 7})),
      MapEntry('2026-10-02', _record({kMorningFieldId: ''})), // 実質空
    ];
    final diaries = [
      MapEntry('2026-10-02', <String, dynamic>{'text': '本文'}),
      MapEntry('2026-10-03', <String, dynamic>{'text': '  '}), // 本文なし
    ];

    test('記録と日記を日付で重ね、どちらか片方だけの日も残す', () {
      final days = mergeDays(records, diaries);
      expect(days.map((d) => d.key), ['2026-10-01', '2026-10-02']);
      expect(numberOf(days.first.value, kSleepFieldId), 7.0);
      expect(days.last.value['diary'], '本文');
      expect(days.last.value.containsKey('values'), isFalse);
    });

    test('記録をつけた日は「値が1つでもある日」と「本文がある日」の和', () {
      expect(recordedDates(records, diaries), {'2026-10-01', '2026-10-02'});
    });

    test('元の Map を書き換えない', () {
      final values = <String, Object?>{kSleepFieldId: 7};
      final original = [MapEntry('2026-10-01', <String, dynamic>{'values': values})];
      final days = mergeDays(original, const []);
      (days.single.value['values'] as Map)['x'] = 1;
      expect(values.keys, [kSleepFieldId]);
    });
  });

  // 「探偵に話す」の振り分け結果を、表に入れる提案へ直す部分
  group('proposalsFromExtraction', () {
    final fields = [_sleep, _exercise, _mood, _morning];

    test('キーの番号を表の並び順で項目に戻し、型を揃える', () {
      final proposals = proposalsFromExtraction(fields, {
        'f0': 6.5,
        'f1': true,
        'f2': '良い',
        'f3': '授業',
      }, const {});
      expect(proposals.map((p) => p.field.id), [
        kSleepFieldId,
        kExerciseFieldId,
        kMoodFieldId,
        kMorningFieldId,
      ]);
      expect(proposals.first.value, 6.5);
      expect(proposals.every((p) => p.current == null), isTrue);
    });

    test('型の合わない値・選択肢に無い値・空は提案しない', () {
      final proposals = proposalsFromExtraction(fields, {
        'f0': 'たくさん',
        'f1': 'はい',
        'f2': '最高',
        'f3': '  ',
      }, const {});
      expect(proposals, isEmpty);
    });

    test('数値が文字列で返ってきても読む', () {
      final proposals = proposalsFromExtraction(fields, {'f0': '7.5'}, const {});
      expect(proposals.single.value, 7.5);
    });

    test('今の値と同じ提案は出さず、違う値は今の値を添えて出す', () {
      final proposals = proposalsFromExtraction(
        fields,
        {'f0': 7, 'f3': '散歩した'},
        {kSleepFieldId: 7.0, kMorningFieldId: '授業'},
      );
      expect(proposals.single.field.id, kMorningFieldId);
      expect(proposals.single.current, '授業');
    });

    test('返答に無い項目・範囲外のキーは無視する', () {
      final proposals = proposalsFromExtraction(fields, {
        'f9': 1,
        'other': true,
      }, const {});
      expect(proposals, isEmpty);
    });
  });

  group('fieldIndex', () {
    test('使っていない項目・閉じた目標の項目も引ける', () {
      const unused = RecordField(id: 'u', label: '昔の項目', active: false);
      const closed = Goal(
        id: 'g',
        title: '昔の目標',
        status: GoalStatus.solved,
        actions: [GoalAction(id: 'j', label: 'ジム')],
      );
      final index = fieldIndex([unused], [closed]);
      expect(index.keys, containsAll(['u', 'goal_j']));
      expect(index['goal_j']!.promptLabel, '目標「昔の目標」の「ジム」');
    });
  });
}
