import 'package:flutter_test/flutter_test.dart';
import 'package:nikkinext/models/goal.dart';
import 'package:nikkinext/models/record_field.dart';

// 記録の型（RecordField）の保存と読み出しを検証する。
//
// ここを固める理由:
// 型や出所は壊れても画面がエラーにならず、「入力欄が違う」「印が出ない」
// という形で静かに間違う。とくに、出所を持たない項目を「自分で足した」と
// 断定しないこと、型の読めない値で項目ごと壊さないことは機械で確かめておきたい。
void main() {
  group('FieldKind', () {
    test('保存文字列と往復する', () {
      for (final kind in FieldKind.values) {
        expect(fieldKindFrom(fieldKindTo(kind)), kind);
      }
    });

    test('未知の値はテキストに倒す（表示だけはできるように）', () {
      expect(fieldKindFrom(null), FieldKind.text);
      expect(fieldKindFrom('date'), FieldKind.text);
    });
  });

  group('FieldSource', () {
    test('保存文字列と往復する', () {
      for (final source in FieldSource.values) {
        expect(fieldSourceFrom(fieldSourceTo(source)), source);
      }
    });

    test('未知の値と欠損は null（自分で足したと決めつけない）', () {
      expect(fieldSourceFrom(null), isNull);
      expect(fieldSourceFrom('Consult'), isNull);
    });
  });

  group('RecordField', () {
    test('toMap → fromMap で中身が保たれる', () {
      const field = RecordField(
        id: '${kCustomFieldPrefix}x',
        label: '天気',
        kind: FieldKind.choice,
        choices: ['晴れ', '雨'],
        weekdays: [6, 7],
        source: FieldSource.consult,
        useInDiary: false,
        active: false,
      );
      final loaded = RecordField.fromMap(field.toMap());
      expect(loaded.id, field.id);
      expect(loaded.label, '天気');
      expect(loaded.kind, FieldKind.choice);
      expect(loaded.choices, ['晴れ', '雨']);
      expect(loaded.weekdays, [6, 7]);
      expect(loaded.source, FieldSource.consult);
      expect(loaded.useInDiary, isFalse);
      expect(loaded.active, isFalse);
    });

    test('出所が無ければキーごと書かない', () {
      const field = RecordField(id: 'a', label: 't');
      expect(field.toMap().containsKey('source'), isFalse);
    });

    test('欠けた項目は既定値で読む（使う・日記に使う）', () {
      final loaded = RecordField.fromMap(const {'id': 'a', 'label': 't'});
      expect(loaded.active, isTrue);
      expect(loaded.useInDiary, isTrue);
      expect(loaded.source, isNull);
    });

    test('カスタム項目だけが削除できる扱いになる', () {
      expect(
        const RecordField(id: '${kCustomFieldPrefix}a', label: 't').isCustom,
        isTrue,
      );
      expect(
        const RecordField(id: kSleepFieldId, label: '睡眠時間').isCustom,
        isFalse,
      );
    });
  });

  group('RecordField.fromGoalAction', () {
    const goal = Goal(id: 'g1', title: '5kg減らす');

    test('数値の行動項目は数値型、id は回答キー、日記には使わない', () {
      const action = GoalAction(
        id: 'w',
        label: '体重',
        type: GoalActionType.numeric,
        unit: 'kg',
        target: 60,
      );
      final field = RecordField.fromGoalAction(goal, action);
      expect(field.id, action.answerKey);
      expect(field.kind, FieldKind.numeric);
      expect(field.unit, 'kg');
      expect(field.target, 60);
      expect(field.useInDiary, isFalse);
      expect(field.isGoal, isTrue);
    });

    test('チェックの行動項目は はい／いいえ型', () {
      const action = GoalAction(id: 'j', label: 'ジムに行く');
      expect(
        RecordField.fromGoalAction(goal, action).kind,
        FieldKind.yesNo,
      );
    });

    test('AI へ渡すラベルには目標名が付く（同名の項目を区別するため）', () {
      const action = GoalAction(id: 'j', label: 'ジムに行く');
      expect(
        RecordField.fromGoalAction(goal, action).promptLabel,
        '目標「5kg減らす」の「ジムに行く」',
      );
      expect(
        const RecordField(id: 'a', label: '睡眠時間').promptLabel,
        '睡眠時間',
      );
    });
  });

  group('kPresetFields', () {
    test('id が重複しない', () {
      final ids = kPresetFields.map((f) => f.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('分析室が値を引くプリセットが揃っている', () {
      final ids = kPresetFields.map((f) => f.id).toSet();
      expect(
        ids,
        containsAll([
          kSleepFieldId,
          kMoodFieldId,
          kExerciseFieldId,
          kStudyFieldId,
        ]),
      );
    });

    test('プリセットは出所が preset', () {
      expect(
        kPresetFields.every((f) => f.source == FieldSource.preset),
        isTrue,
      );
    });
  });
}
