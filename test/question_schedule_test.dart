import 'package:flutter_test/flutter_test.dart';
import 'package:nikkinext/core/question_schedule.dart';
import 'package:nikkinext/models/record_field.dart';

void main() {
  group('isFieldShownOn', () {
    // 2026-10-05 は月曜日、2026-10-11 は日曜日
    final monday = DateTime(2026, 10, 5);
    final sunday = DateTime(2026, 10, 11);

    test('既定（全曜日）は毎日出す', () {
      const field = RecordField(id: 'a', label: 't');
      for (var i = 0; i < 7; i++) {
        expect(isFieldShownOn(field, monday.add(Duration(days: i))), isTrue);
      }
    });

    test('指定した曜日だけ出す（1=月, 7=日）', () {
      const field = RecordField(id: 'a', label: 't', weekdays: [7]);
      expect(isFieldShownOn(field, sunday), isTrue);
      expect(isFieldShownOn(field, monday), isFalse);
    });
  });

  group('RecordField.fromMap の曜日', () {
    test('weekdays の無いデータは毎日扱い', () {
      final field = RecordField.fromMap({'id': 'a', 'label': 't'});
      expect(field.weekdays, RecordField.allWeekdays);
    });

    test('空リストや範囲外の値は救済・除外する', () {
      expect(
        RecordField.fromMap({
          'id': 'a',
          'label': 't',
          'weekdays': <int>[],
        }).weekdays,
        RecordField.allWeekdays,
      );
      expect(
        RecordField.fromMap({
          'id': 'a',
          'label': 't',
          'weekdays': [5, 0, 1, 8, 1],
        }).weekdays,
        [1, 5],
      );
    });

    test('toMap と往復しても曜日が保たれる', () {
      const field = RecordField(id: 'a', label: 't', weekdays: [2, 4]);
      expect(RecordField.fromMap(field.toMap()).weekdays, [2, 4]);
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
      expect(describeWeekdays(RecordField.allWeekdays), '毎日');
      expect(describeWeekdays([1, 2, 3, 4, 5]), '平日');
      expect(describeWeekdays([6, 7]), '土日');
      expect(describeWeekdays([5, 1, 3]), '月・水・金');
    });
  });
}
