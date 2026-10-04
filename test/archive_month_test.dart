import 'package:flutter_test/flutter_test.dart';
import 'package:nikkinext/models/archive_month.dart';

void main() {
  group('groupByMonth', () {
    test('空のマップなら空のリストを返す', () {
      expect(groupByMonth({}), isEmpty);
    });

    test('同じ月の日記を件数にまとめる', () {
      final result = groupByMonth({
        '2026-09-01': 'a',
        '2026-09-15': 'b',
        '2026-09-30': 'c',
      });
      expect(result, hasLength(1));
      expect(result.single.year, 2026);
      expect(result.single.month, 9);
      expect(result.single.count, 3);
    });

    test('新しい月が先頭になる', () {
      final result = groupByMonth({
        '2026-07-10': 'a',
        '2026-09-01': 'b',
        '2026-08-20': 'c',
      });
      expect(result.map((m) => m.month), [9, 8, 7]);
    });

    test('年をまたいでも新しい順になる（2025年12月 < 2026年1月）', () {
      final result = groupByMonth({
        '2025-12-31': 'a',
        '2026-01-01': 'b',
      });
      expect(result.map((m) => [m.year, m.month]), [
        [2026, 1],
        [2025, 12],
      ]);
    });

    test('1桁の月と2桁の月が混ざっても順序が崩れない（9月 < 10月）', () {
      final result = groupByMonth({
        '2026-09-30': 'a',
        '2026-10-01': 'b',
      });
      expect(result.map((m) => m.month), [10, 9]);
    });
  });

  group('groupByMonth の日付検証', () {
    test('うるう年の2月29日は受け入れる（2024年・2000年）', () {
      expect(() => groupByMonth({'2024-02-29': 'a'}), returnsNormally);
      expect(() => groupByMonth({'2000-02-29': 'a'}), returnsNormally);
    });

    test('うるう年でない年の2月29日はエラー（2025年・1900年・2100年）', () {
      for (final date in ['2025-02-29', '1900-02-29', '2100-02-29']) {
        expect(
          () => groupByMonth({date: 'a'}),
          throwsFormatException,
          reason: date,
        );
      }
    });

    test('存在しない日付はエラー（2月30日・4月31日・13月）', () {
      for (final date in ['2026-02-30', '2026-04-31', '2026-13-01']) {
        expect(
          () => groupByMonth({date: 'a'}),
          throwsFormatException,
          reason: date,
        );
      }
    });

    test('形式が違うキーはエラー', () {
      for (final date in ['', 'latest', '2026-9-1', '20260901', '2026-09-01x']) {
        expect(
          () => groupByMonth({date: 'a'}),
          throwsFormatException,
          reason: date,
        );
      }
    });

    test('不正なキーが1つ混ざっていたら全体がエラーになる', () {
      expect(
        () => groupByMonth({'2026-09-01': 'a', 'broken': 'b'}),
        throwsFormatException,
      );
    });
  });
}
