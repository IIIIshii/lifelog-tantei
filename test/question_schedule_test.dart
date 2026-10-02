import 'package:flutter_test/flutter_test.dart';
import 'package:nikkinext/core/question_schedule.dart';
import 'package:nikkinext/models/user_settings.dart';

void main() {
  group('isAskedOn', () {
    // 2026-10-05 は月曜日、2026-10-11 は日曜日
    final monday = DateTime(2026, 10, 5);
    final sunday = DateTime(2026, 10, 11);

    test('既定（全曜日）は毎日出題する', () {
      const q = CustomQuestion(id: 'a', text: 't');
      for (var i = 0; i < 7; i++) {
        expect(isAskedOn(q, monday.add(Duration(days: i))), isTrue);
      }
    });

    test('指定した曜日だけ出題する（1=月, 7=日）', () {
      const q = CustomQuestion(id: 'a', text: 't', weekdays: [7]);
      expect(isAskedOn(q, sunday), isTrue);
      expect(isAskedOn(q, monday), isFalse);
    });
  });

  group('CustomQuestion.fromMap', () {
    test('weekdays の無い旧データは毎日扱い', () {
      final q = CustomQuestion.fromMap({'id': 'a', 'text': 't'});
      expect(q.weekdays, CustomQuestion.allWeekdays);
    });

    test('空リストや範囲外の値は救済・除外する', () {
      expect(
        CustomQuestion.fromMap({'id': 'a', 'text': 't', 'weekdays': []})
            .weekdays,
        CustomQuestion.allWeekdays,
      );
      expect(
        CustomQuestion.fromMap(
          {'id': 'a', 'text': 't', 'weekdays': [5, 0, 1, 8, 1]},
        ).weekdays,
        [1, 5],
      );
    });

    test('toMap と往復しても曜日が保たれる', () {
      const q = CustomQuestion(id: 'a', text: 't', weekdays: [2, 4]);
      expect(CustomQuestion.fromMap(q.toMap()).weekdays, [2, 4]);
    });
  });

  group('toggleWeekday', () {
    test('オフ→オン・オン→オフ（昇順を保つ）', () {
      expect(toggleWeekday([1, 5], 3), [1, 3, 5]);
      expect(toggleWeekday([1, 3, 5], 3), [1, 5]);
    });

    test('最後の1曜日はオフにできない', () {
      expect(toggleWeekday([6], 6), [6]);
    });
  });

  group('describeWeekdays', () {
    test('代表的なパターンを短く表す', () {
      expect(describeWeekdays(CustomQuestion.allWeekdays), '毎日');
      expect(describeWeekdays([1, 2, 3, 4, 5]), '平日');
      expect(describeWeekdays([6, 7]), '土日');
      expect(describeWeekdays([5, 1, 3]), '月・水・金');
    });
  });
}
