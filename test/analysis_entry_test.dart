import 'package:flutter_test/flutter_test.dart';
import 'package:nikkinext/models/analysis_entry.dart';

// 積んでいく所見（analyses/{autoId}）の読み書きと、画面に出す1件の選び方を検証する。
//
// ここを固める理由:
// 「今日のコメント」を日付で絞り損ねると、昨日のコメントが今日のものとして出る。
// 種類の無い古いドキュメント（上書き方式だった頃の latest / today）を拾うと、
// 何の所見か分からないものが綴りに混ざる。どちらも画面はエラーにならない。
AnalysisEntry _entry(String id, AnalysisKind kind, String date) =>
    AnalysisEntry(id: id, kind: kind, text: '本文$id', date: date);

void main() {
  group('AnalysisEntry', () {
    test('toMap → fromMap で中身が保たれる', () {
      const entry = AnalysisEntry(
        id: 'a',
        kind: AnalysisKind.period,
        text: '所見',
        date: '2026-10-13',
        periodDays: 14,
      );
      final loaded = AnalysisEntry.fromMap('a', entry.toMap())!;
      expect(loaded.kind, AnalysisKind.period);
      expect(loaded.text, '所見');
      expect(loaded.date, '2026-10-13');
      expect(loaded.periodDays, 14);
    });

    test('今日のコメントは期間を書かない', () {
      const entry = AnalysisEntry(
        id: 'a',
        kind: AnalysisKind.daily,
        text: 'コメント',
        date: '2026-10-13',
      );
      expect(entry.toMap().containsKey('periodDays'), isFalse);
    });

    test('種類の無い古いドキュメント・本文の無いものは読まない', () {
      expect(
        AnalysisEntry.fromMap('latest', const {'text': '昔の所見', 'periodDays': 14}),
        isNull,
      );
      expect(
        AnalysisEntry.fromMap('x', const {'kind': 'daily', 'text': '  '}),
        isNull,
      );
    });
  });

  group('latestAnalysis', () {
    final newestFirst = [
      _entry('3', AnalysisKind.daily, '2026-10-12'),
      _entry('2', AnalysisKind.period, '2026-10-12'),
      _entry('1', AnalysisKind.period, '2026-10-01'),
    ];

    test('指定の種類で一番新しいものを選ぶ', () {
      expect(latestAnalysis(newestFirst, AnalysisKind.period)!.id, '2');
    });

    test('日付を指定すると、その日に書いたものだけ（昨日のコメントを今日に出さない）', () {
      expect(
        latestAnalysis(newestFirst, AnalysisKind.daily, onDate: '2026-10-13'),
        isNull,
      );
      expect(
        latestAnalysis(
          newestFirst,
          AnalysisKind.daily,
          onDate: '2026-10-12',
        )!.id,
        '3',
      );
    });
  });

  test('analysisKind は保存文字列と往復し、読めない値は null', () {
    for (final kind in AnalysisKind.values) {
      expect(analysisKindFrom(analysisKindTo(kind)), kind);
    }
    expect(analysisKindFrom(null), isNull);
    expect(analysisKindFrom('weekly'), isNull);
  });
}
