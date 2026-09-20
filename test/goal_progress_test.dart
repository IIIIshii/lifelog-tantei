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

// Firestore から読んだエントリ1件の形を作るヘルパー。
// getRecentEntries は (YYYY-MM-DD, ドキュメントのMap) を返すのでそれに合わせる。
MapEntry<String, Map<String, dynamic>> _entry(
  String date, {
  Map<String, dynamic>? answers,
  Map<String, dynamic>? numericAnswers,
}) {
  return MapEntry(date, <String, dynamic>{
    'answers': ?answers,
    'numericAnswers': ?numericAnswers,
  });
}

void main() {
  const key = 'goal_a1';

  group('checkRate', () {
    test('答えた日だけを母数にする（記録の無い日は率を下げない）', () {
      final entries = [
        _entry('2026-09-05', answers: {key: kGoalDone}),
        _entry('2026-09-04', answers: {key: kGoalNotDone}),
        _entry('2026-09-03'), // この項目には答えていない日
        _entry('2026-09-02', answers: {'food': 'カレー'}), // 別の質問だけ答えた日
      ];
      expect(checkRate(entries, key), 0.5);
    });

    test('全部達成なら 1.0、全部未達なら 0.0', () {
      final done = [
        _entry('2026-09-05', answers: {key: kGoalDone}),
        _entry('2026-09-04', answers: {key: kGoalDone}),
      ];
      expect(checkRate(done, key), 1.0);

      final notDone = [
        _entry('2026-09-05', answers: {key: kGoalNotDone}),
      ];
      expect(checkRate(notDone, key), 0.0);
    });

    test('一度も答えていなければ null（0%と表示させない）', () {
      expect(checkRate(const [], key), isNull);
      expect(checkRate([_entry('2026-09-05')], key), isNull);
      expect(
        checkRate([
          _entry('2026-09-05', answers: {'goal_other': kGoalDone}),
        ], key),
        isNull,
      );
    });

    test('想定外の文字列は母数にも分子にも入れない', () {
      final entries = [
        _entry('2026-09-05', answers: {key: kGoalDone}),
        _entry('2026-09-04', answers: {key: 'たぶん'}), // 手動編集や旧データ
        _entry('2026-09-03', answers: {key: ''}), // 空文字
      ];
      expect(checkRate(entries, key), 1.0);
    });
  });

  group('latestNumeric', () {
    test('エントリの並び順に関わらず日付が新しい方を採る', () {
      final entries = [
        _entry('2026-09-03', numericAnswers: {key: 63.0}),
        _entry('2026-09-05', numericAnswers: {key: 62.5}),
        _entry('2026-09-04', numericAnswers: {key: 62.8}),
      ];
      expect(latestNumeric(entries, key), 62.5);
    });

    test('月・年をまたいでも新しい方を採る', () {
      final entries = [
        _entry('2026-12-31', numericAnswers: {key: 70.0}),
        _entry('2027-01-01', numericAnswers: {key: 69.0}),
      ];
      expect(latestNumeric(entries, key), 69.0);
    });

    test('記録が無ければ null', () {
      expect(latestNumeric(const [], key), isNull);
      expect(latestNumeric([_entry('2026-09-05')], key), isNull);
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
  // 目標が複数になると 'goal_' 接頭辞だけでは足りない。1件答えただけで
  // 全部の目標が記録済みに見えると、バッジが何も言っていないのと同じになる。
  group('hasAnswerForGoal', () {
    const weight = GoalAction(
      id: 'w1',
      label: '体重',
      type: GoalActionType.numeric,
    );
    const gym = GoalAction(id: 'g1', label: 'ジムに行く');
    const reading = GoalAction(id: 'r1', label: '読んだページ数');

    const diet = Goal(id: 'diet', title: '5kg減らす', actions: [weight, gym]);
    const books = Goal(id: 'books', title: '積ん読を減らす', actions: [reading]);

    Map<String, dynamic> entryWith(Map<String, dynamic> answers) =>
        <String, dynamic>{'answers': answers};

    test('その目標の項目に答えていれば true', () {
      final entry = entryWith({'goal_w1': '62.5'});
      expect(hasAnswerForGoal(entry, diet), isTrue);
    });

    test('別の目標の項目にだけ答えた日は false', () {
      final entry = entryWith({'goal_r1': '30'});
      expect(hasAnswerForGoal(entry, diet), isFalse);
      expect(hasAnswerForGoal(entry, books), isTrue);
    });

    test('空文字の回答（スキップ）は答えたことにしない', () {
      final entry = entryWith({'goal_w1': ''});
      expect(hasAnswerForGoal(entry, diet), isFalse);
    });

    test('行動項目を持たない目標は常に false', () {
      final entry = entryWith({'goal_w1': '62.5'});
      expect(
        hasAnswerForGoal(entry, const Goal(id: 'x', title: '方針だけ')),
        isFalse,
      );
    });

    test('その日のエントリが無ければ false', () {
      expect(hasAnswerForGoal(null, diet), isFalse);
      expect(hasAnswerForGoal(const <String, dynamic>{}, diet), isFalse);
    });

    test('goalsRecordedIn は答えた目標の id だけを集める', () {
      final entry = entryWith({'goal_g1': '達成', 'sleep': '7時間'});
      expect(goalsRecordedIn(entry, const [diet, books]), {'diet'});
      expect(goalsRecordedIn(null, const [diet, books]), isEmpty);
    });
  });
}
