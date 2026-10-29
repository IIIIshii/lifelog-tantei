import 'package:flutter_test/flutter_test.dart';
import 'package:nikkinext/core/period_stats.dart';
import 'package:nikkinext/models/record_field.dart';
import 'package:nikkinext/prompts/diary_prompts.dart';

// 所見に渡す期間の集計を検証する。
//
// 同じ入力なら同じ数字になること、記録が少ない期間で傾向を言わせないこと、
// 「未記入」と「いいえ・0 を記録した」を取り違えないことを固める。
// AI が文章から暗算していた頃は、ここがぶれていた。
void main() {
  const sleep = RecordField(
    id: 'sleep',
    label: '睡眠時間',
    kind: FieldKind.numeric,
    unit: '時間',
  );
  const exercise = RecordField(
    id: 'exercise',
    label: '運動した',
    kind: FieldKind.yesNo,
  );
  const mood = RecordField(
    id: 'mood',
    label: '今日の気分',
    kind: FieldKind.choice,
    choices: ['良い', 'ふつう', '悪い'],
  );
  const memo = RecordField(id: 'memo', label: 'メモ');
  final fields = {
    for (final f in [sleep, exercise, mood, memo]) f.id: f,
  };

  MapEntry<String, Map<String, dynamic>> day(
    String date, {
    Map<String, dynamic>? values,
    String? diary,
  }) => MapEntry(date, {
    'values': ?values,
    'diary': ?diary,
  });

  // 2026-10-14 〜 2026-10-27 の14日間（前半 10/14〜10/20、後半 10/21〜10/27）
  final end = DateTime(2026, 10, 27);

  group('summarizePeriod の日数', () {
    test('記録のあった日・日記のあった日・何もなかった日を数える', () {
      final summary = summarizePeriod(
        [
          day('2026-10-20', values: {'sleep': 7}),
          day('2026-10-21', diary: '散歩した'),
          day('2026-10-22', values: {'sleep': 6}, diary: '仕事'),
        ],
        fields,
        end: end,
        periodDays: 14,
      );
      expect(summary.recordedDays, 2);
      expect(summary.diaryDays, 2);
      expect(summary.emptyDays, 11); // 14 - (記録か日記のある3日)
    });

    test('期間の外の日は数えない', () {
      final summary = summarizePeriod(
        [
          day('2026-10-13', values: {'sleep': 7}), // 期間の前日
          day('2026-10-28', values: {'sleep': 7}), // 期間の翌日
          day('2026-10-27', values: {'sleep': 7}),
        ],
        fields,
        end: end,
        periodDays: 14,
      );
      expect(summary.recordedDays, 1);
    });

    test('月をまたぐ期間でも日付キーが合う', () {
      final summary = summarizePeriod(
        [
          day('2026-09-30', values: {'sleep': 7}),
          day('2026-10-01', values: {'sleep': 8}),
        ],
        fields,
        end: DateTime(2026, 10, 3),
        periodDays: 5,
      );
      expect(summary.recordedDays, 2);
      expect(summary.start, DateTime(2026, 9, 29));
    });
  });

  group('数値項目', () {
    test('平均・最小・最大を出す', () {
      final summary = summarizePeriod(
        [
          day('2026-10-20', values: {'sleep': 6}),
          day('2026-10-21', values: {'sleep': 7.5}),
          day('2026-10-22', values: {'sleep': 9}),
        ],
        fields,
        end: end,
        periodDays: 14,
      );
      final line = summary.fieldLines.singleWhere((l) => l.startsWith('睡眠時間'));
      expect(line, contains('記録3日'));
      expect(line, contains('平均7.5時間'));
      expect(line, contains('最小6〜最大9'));
    });

    test('前半と後半の記録が2日ずつあれば、平均の変化を添える', () {
      final summary = summarizePeriod(
        [
          day('2026-10-15', values: {'sleep': 5}),
          day('2026-10-16', values: {'sleep': 6}),
          day('2026-10-24', values: {'sleep': 7}),
          day('2026-10-25', values: {'sleep': 8}),
        ],
        fields,
        end: end,
        periodDays: 14,
      );
      final line = summary.fieldLines.singleWhere((l) => l.startsWith('睡眠時間'));
      expect(line, contains('前半の平均5.5時間→後半の平均7.5時間'));
    });

    test('片方の半分に記録が足りなければ、増減は言わない', () {
      final summary = summarizePeriod(
        [
          day('2026-10-15', values: {'sleep': 5}),
          day('2026-10-24', values: {'sleep': 7}),
          day('2026-10-25', values: {'sleep': 8}),
        ],
        fields,
        end: end,
        periodDays: 14,
      );
      final line = summary.fieldLines.singleWhere((l) => l.startsWith('睡眠時間'));
      expect(line, isNot(contains('前半')));
    });

    test('値が1つも無い項目は行にしない', () {
      final summary = summarizePeriod(
        [
          day('2026-10-20', values: {'exercise': true}),
        ],
        fields,
        end: end,
        periodDays: 14,
      );
      expect(summary.fieldLines.any((l) => l.startsWith('睡眠時間')), isFalse);
    });
  });

  group('はい／いいえ・選択肢・自由記述', () {
    test('いいえを記録した日は、未記入ではなく「記録した日」に数える', () {
      final summary = summarizePeriod(
        [
          day('2026-10-20', values: {'exercise': true}),
          day('2026-10-21', values: {'exercise': false}),
          day('2026-10-22', values: {'sleep': 7}), // 運動は未記入
        ],
        fields,
        end: end,
        periodDays: 14,
      );
      final line = summary.fieldLines.singleWhere((l) => l.startsWith('運動した'));
      expect(line, '運動した: 記録2日のうち、はいが1日');
    });

    test('選択肢は件数の多い順、同数なら名前順で並べる', () {
      final summary = summarizePeriod(
        [
          day('2026-10-20', values: {'mood': 'ふつう'}),
          day('2026-10-21', values: {'mood': '良い'}),
          day('2026-10-22', values: {'mood': 'ふつう'}),
          day('2026-10-23', values: {'mood': '悪い'}),
        ],
        fields,
        end: end,
        periodDays: 14,
      );
      final line = summary.fieldLines.singleWhere((l) => l.startsWith('今日の気分'));
      expect(line, '今日の気分: ふつう2日 / 悪い1日 / 良い1日');
    });

    test('自由記述の項目は集計しない', () {
      final summary = summarizePeriod(
        [
          day('2026-10-20', values: {'memo': 'カフェで読書'}),
        ],
        fields,
        end: end,
        periodDays: 14,
      );
      expect(summary.fieldLines.any((l) => l.startsWith('メモ')), isFalse);
    });
  });

  group('記録が少ない期間', () {
    test('記録のあった日が3日に満たなければ、傾向は言えないと伝える', () {
      final summary = summarizePeriod(
        [
          day('2026-10-20', values: {'sleep': 7}),
          day('2026-10-21', values: {'sleep': 6}),
        ],
        fields,
        end: end,
        periodDays: 14,
      );
      expect(summary.isSparse, isTrue);
      expect(summary.toPromptBlock(), contains('まだ言えない'));
    });

    test('3日あれば、傾向を止める注意は付けない', () {
      final summary = summarizePeriod(
        [
          day('2026-10-20', values: {'sleep': 7}),
          day('2026-10-21', values: {'sleep': 6}),
          day('2026-10-22', values: {'sleep': 8}),
        ],
        fields,
        end: end,
        periodDays: 14,
      );
      expect(summary.isSparse, isFalse);
      expect(summary.toPromptBlock(), isNot(contains('まだ言えない')));
    });

    test('記録が1日も無くても落ちない', () {
      final summary = summarizePeriod(
        const [],
        fields,
        end: end,
        periodDays: 14,
      );
      expect(summary.recordedDays, 0);
      expect(summary.emptyDays, 14);
      expect(summary.toPromptBlock(), contains('まだ言えない'));
    });
  });

  group('同じ入力なら同じ出力', () {
    test('2回呼んでも、集計の文章は完全に一致する', () {
      final days = [
        day('2026-10-20', values: {'sleep': 7, 'mood': '良い'}),
        day('2026-10-22', values: {'sleep': 6, 'mood': 'ふつう'}),
        day('2026-10-24', values: {'sleep': 8, 'mood': '良い'}),
      ];
      String run() => summarizePeriod(
        days,
        fields,
        end: end,
        periodDays: 14,
      ).toPromptBlock();
      expect(run(), run());
    });
  });

  group('所見のプロンプトへの組み込み', () {
    final days = [
      day('2026-10-20', values: {'sleep': 7}, diary: '散歩した'),
    ];

    test('集計があれば、本文と依頼のあいだに入り、数字をそのまま使わせる', () {
      final stats = summarizePeriod(
        days,
        fields,
        end: end,
        periodDays: 14,
      ).toPromptBlock();
      final prompt = DiaryPrompts.buildAnalysisPrompt(
        days,
        fields: fields,
        statsBlock: stats,
      );
      expect(prompt, contains('【集計'));
      expect(prompt, contains('数字は【集計】の値をそのまま使い'));
      expect(prompt.indexOf('【集計'), lessThan(prompt.indexOf('【依頼内容】')));
    });

    test('集計が無ければ、従来どおりの形のまま', () {
      final prompt = DiaryPrompts.buildAnalysisPrompt(days, fields: fields);
      expect(prompt, isNot(contains('【集計')));
      expect(prompt, isNot(contains('そのまま使い')));
    });
  });
}
