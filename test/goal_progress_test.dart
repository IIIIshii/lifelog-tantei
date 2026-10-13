import 'package:flutter_test/flutter_test.dart';
import 'package:nikkinext/core/goal_progress.dart';
import 'package:nikkinext/models/goal.dart';

// 目標の進捗（達成率・数値の推移・経過日数）の算出を検証する。
//
// ここを固める理由:
// 「記録の無い日」と「未達と答えた日」を混同すると、続けるほど達成率が
// 下がって見えるという、継続の手応えを折る表示になる。母数の数え方は
// UIからは見えないので機械で確かめておきたい。
// 経過日数も日付境界（月またぎ・うるう年・夏時間）で1日ずれやすい。

// Firestore から読んだ日々の記録1件の形を作るヘルパー。
// getRecentRecords は (YYYY-MM-DD, ドキュメントのMap) を返すのでそれに合わせる。
MapEntry<String, Map<String, dynamic>> _record(
  String date, [
  Map<String, Object?>? values,
]) {
  return MapEntry(date, <String, dynamic>{'values': ?values});
}

void main() {
  const key = 'goal_a1';

  group('checkRate', () {
    test('答えた日だけを母数にする（記録の無い日は率を下げない）', () {
      final records = [
        _record('2026-09-05', {key: true}),
        _record('2026-09-04', {key: false}),
        _record('2026-09-03'), // この日は何も記録していない
        _record('2026-09-02', {'food': 'カレー'}), // 別の項目だけ記録した日
      ];
      expect(checkRate(records, key), 0.5);
    });

    test('全部達成なら 1.0、全部未達なら 0.0', () {
      final done = [
        _record('2026-09-05', {key: true}),
        _record('2026-09-04', {key: true}),
      ];
      expect(checkRate(done, key), 1.0);

      final notDone = [
        _record('2026-09-05', {key: false}),
      ];
      expect(checkRate(notDone, key), 0.0);
    });

    test('一度も答えていなければ null（0%と表示させない）', () {
      expect(checkRate(const [], key), isNull);
      expect(checkRate([_record('2026-09-05')], key), isNull);
      expect(
        checkRate([
          _record('2026-09-05', {'goal_other': true}),
        ], key),
        isNull,
      );
    });

    test('bool 以外の値は母数にも分子にも入れない', () {
      final records = [
        _record('2026-09-05', {key: true}),
        _record('2026-09-04', {key: '達成'}), // 手で書き換えたデータなど
        _record('2026-09-03', {key: ''}),
      ];
      expect(checkRate(records, key), 1.0);
    });
  });

  group('checkCounts', () {
    test('答えた日を母数に、達成した日を分子に数える', () {
      final records = [
        _record('2026-09-01', {key: true}),
        _record('2026-09-02', {key: false}),
        _record('2026-09-03', {key: true}),
      ];
      final counts = checkCounts(records, key);
      expect(counts.answered, 3);
      expect(counts.done, 2);
    });

    test('一度も答えていなければ 0 / 0', () {
      final counts = checkCounts(const [], key);
      expect(counts.answered, 0);
      expect(counts.done, 0);
    });
  });

  group('latestNumeric', () {
    test('記録の並び順に関わらず日付が新しい方を採る', () {
      final records = [
        _record('2026-09-03', {key: 63.0}),
        _record('2026-09-05', {key: 62.5}),
        _record('2026-09-04', {key: 62.8}),
      ];
      expect(latestNumeric(records, key), 62.5);
    });

    test('月・年をまたいでも新しい方を採る', () {
      final records = [
        _record('2026-12-31', {key: 70}),
        _record('2027-01-01', {key: 69}),
      ];
      expect(latestNumeric(records, key), 69.0);
    });

    test('記録が無ければ null', () {
      expect(latestNumeric(const [], key), isNull);
      expect(latestNumeric([_record('2026-09-05')], key), isNull);
    });
  });

  group('numericSeries', () {
    test('値のある日だけを古い順に並べる', () {
      final records = [
        _record('2026-09-05', {key: 62.5}),
        _record('2026-09-03', {key: 63}),
        _record('2026-09-04'),
      ];
      final series = numericSeries(records, key);
      expect(series.map((p) => p.date), ['2026-09-03', '2026-09-05']);
      expect(series.map((p) => p.value), [63.0, 62.5]);
    });
  });

  group('daysSince', () {
    test('立てた当日は 0、翌日は 1', () {
      expect(daysSince('2026-09-19', DateTime(2026, 9, 19)), 0);
      expect(daysSince('2026-09-19', DateTime(2026, 9, 20)), 1);
    });

    test('時刻を持つ DateTime でも日付だけで数える', () {
      expect(daysSince('2026-09-19', DateTime(2026, 9, 20, 23, 59)), 1);
    });

    test('月をまたいでも正しく数える', () {
      expect(daysSince('2026-08-31', DateTime(2026, 9, 1)), 1);
      expect(daysSince('2026-09-01', DateTime(2026, 10, 1)), 30);
    });

    test('うるう年の2月をまたいでも正しく数える', () {
      expect(daysSince('2028-02-28', DateTime(2028, 3, 1)), 2); // 2/29がある
      expect(daysSince('2026-02-28', DateTime(2026, 3, 1)), 1); // 平年
    });

    test('夏時間の切替をまたいでも1日ずれない', () {
      // 多くの地域で夏時間が切り替わる3月末・10月末をまたぐ期間
      expect(daysSince('2026-03-28', DateTime(2026, 3, 30)), 2);
      expect(daysSince('2026-10-24', DateTime(2026, 10, 26)), 2);
    });

    test('未設定・不正な形式は 0（表示を壊さない）', () {
      expect(daysSince('', DateTime(2026, 9, 19)), 0);
      expect(daysSince('2026-09', DateTime(2026, 9, 19)), 0);
      expect(daysSince('きのう', DateTime(2026, 9, 19)), 0);
    });

    test('未来の日付でもマイナスにはしない', () {
      expect(daysSince('2026-09-20', DateTime(2026, 9, 19)), 0);
    });
  });

  // ── 目標別の「本日記録済み」判定 ────────────────────────────
  //
  // 目標が複数になると 'goal_' 接頭辞だけでは足りない。1件記録しただけで
  // 全部の目標が記録済みに見えると、バッジが何も言っていないのと同じになる。
  group('hasAnswerForGoal / goalsRecordedIn', () {
    const weight = GoalAction(
      id: 'w1',
      label: '体重',
      type: GoalActionType.numeric,
    );
    const gym = GoalAction(id: 'g1', label: 'ジムに行く');
    const reading = GoalAction(id: 'r1', label: '読んだページ数');

    const diet = Goal(id: 'diet', title: '5kg減らす', actions: [weight, gym]);
    const books = Goal(id: 'books', title: '積ん読を減らす', actions: [reading]);

    Map<String, dynamic> recordWith(Map<String, Object?> values) =>
        <String, dynamic>{'values': values};

    test('その目標の項目に値があれば true', () {
      expect(hasAnswerForGoal(recordWith({'goal_w1': 62.5}), diet), isTrue);
    });

    test('未達（false）も記録したことになる', () {
      expect(hasAnswerForGoal(recordWith({'goal_g1': false}), diet), isTrue);
    });

    test('別の目標の項目にだけ値がある日は false', () {
      final record = recordWith({'goal_r1': 30});
      expect(hasAnswerForGoal(record, diet), isFalse);
      expect(hasAnswerForGoal(record, books), isTrue);
    });

    test('行動項目を持たない目標は常に false', () {
      expect(
        hasAnswerForGoal(
          recordWith({'goal_w1': 62.5}),
          const Goal(id: 'x', title: '方針だけ'),
        ),
        isFalse,
      );
    });

    test('その日の記録が無ければ false', () {
      expect(hasAnswerForGoal(null, diet), isFalse);
      expect(hasAnswerForGoal(const <String, dynamic>{}, diet), isFalse);
    });

    test('goalsRecordedIn は記録した目標の id だけを集める', () {
      final record = recordWith({'goal_w1': 62.5, 'goal_r1': ''});
      expect(goalsRecordedIn(record, const [diet, books]), {'diet'});
      expect(goalsRecordedIn(null, const [diet, books]), isEmpty);
    });
  });

  group('elapsedLabel', () {
    final today = DateTime(2026, 9, 20);

    test('着手からの日数を出す', () {
      const goal = Goal(id: 'g', title: '5kg減らす', createdAt: '2026-09-10');
      expect(elapsedLabel(goal, today), contains('着手から10日'));
    });

    test('期限があれば添える', () {
      const goal = Goal(
        id: 'g',
        title: '5kg減らす',
        createdAt: '2026-09-10',
        deadline: '2026-12-31',
      );
      expect(elapsedLabel(goal, today), contains('2026-12-31'));
    });

    test('着手日が無ければ経過を出さない（今日始めたように見せない）', () {
      const goal = Goal(id: 'g', title: '5kg減らす');
      expect(elapsedLabel(goal, today), isNot(contains('着手から')));
    });

    test('着手日が無く期限だけあるときは期限を出す', () {
      const goal = Goal(id: 'g', title: '5kg減らす', deadline: '2026-12-31');
      expect(elapsedLabel(goal, today), '期限 2026-12-31');
    });
  });
}
