import 'package:flutter_test/flutter_test.dart';
import 'package:nikkinext/core/feeling_cues.dart';
import 'package:nikkinext/prompts/ai_instructions.dart';
import 'package:nikkinext/prompts/diary_prompts.dart';

// 会話から読み取った感じ方の手がかりを、残してよいものだけに絞る判断を検証する。
//
// AI の読み違いや作り話が自己理解のノートに入ると、本人の実感と食い違う仮説が育つ。
// 「根拠が依頼人の発言にある」「決まった語だけ」「上限がある」を固める。
void main() {
  const lines = [
    (role: 'ai', text: '資料作りはどうだった？'),
    (role: 'user', text: '気づいたら 1時間たってた。でも資料の見直しは後回しにした'),
    (role: 'ai', text: '疲れた？'),
    (role: 'user', text: 'うん'),
  ];

  Map<String, String> item(String activity, String feeling, String quote) => {
    'activity': activity,
    'feeling': feeling,
    'quote': quote,
  };

  group('feelingCuesFromExtraction', () {
    test('依頼人の発言にある引用の手がかりを残す', () {
      final cues = feelingCuesFromExtraction([
        item('資料作り', 'absorbed', '気づいたら1時間たってた'), // 空白の違いは無視する
      ], lines);
      expect(cues.length, 1);
      expect(cues.single.feeling, Feeling.absorbed);
      expect(cues.single.activity, '資料作り');
    });

    test('探偵の質問から引いた根拠は捨てる', () {
      final cues = feelingCuesFromExtraction([
        item('資料作り', 'tired', '疲れた？'),
      ], lines);
      expect(cues, isEmpty);
    });

    test('発言のどこにも無い引用（AI の作り話）は捨てる', () {
      final cues = feelingCuesFromExtraction([
        item('資料作り', 'enjoyed', 'すごく楽しかった'),
      ], lines);
      expect(cues, isEmpty);
    });

    test('決まった語にない感じ方は捨てる', () {
      final cues = feelingCuesFromExtraction([
        item('資料作り', 'excited', '気づいたら1時間たってた'),
      ], lines);
      expect(cues, isEmpty);
    });

    test('出来事名が空、形が違う要素は捨てる', () {
      final cues = feelingCuesFromExtraction([
        item('  ', 'absorbed', '気づいたら1時間たってた'),
        'text',
        null,
        {'activity': 'x', 'feeling': 'tired'}, // quote が無い
        {'activity': 1, 'feeling': 'tired', 'quote': 'うん'},
      ], lines);
      expect(cues, isEmpty);
    });

    test('同じ出来事・同じ感じ方は1件にまとめる', () {
      final cues = feelingCuesFromExtraction([
        item('資料作り', 'absorbed', '気づいたら1時間たってた'),
        item('資料作り', 'absorbed', '1時間たってた'),
        item('資料作り', 'avoided', '資料の見直しは後回しにした'),
      ], lines);
      expect(cues.map((c) => c.feeling), [Feeling.absorbed, Feeling.avoided]);
    });

    test('1日の上限を超えたぶんは捨てる', () {
      final many = [
        for (var i = 0; i < kMaxFeelingCuesPerDay + 3; i++)
          item('出来事$i', 'absorbed', '気づいたら1時間たってた'),
      ];
      expect(
        feelingCuesFromExtraction(many, lines).length,
        kMaxFeelingCuesPerDay,
      );
    });

    test('長すぎる出来事名は切り詰める', () {
      final cues = feelingCuesFromExtraction([
        item('あ' * 50, 'absorbed', '気づいたら1時間たってた'),
      ], lines);
      expect(cues.single.activity.length, kMaxActivityLength);
    });

    test('配列でない応答、依頼人の発言が無い会話は空', () {
      expect(feelingCuesFromExtraction({'a': 1}, lines), isEmpty);
      expect(feelingCuesFromExtraction(null, lines), isEmpty);
      expect(
        feelingCuesFromExtraction(
          [item('x', 'tired', '疲れた')],
          const [(role: 'ai', text: '疲れた')],
        ),
        isEmpty,
      );
    });
  });

  group('FeelingCue', () {
    test('保存した形から同じ内容に戻せる', () {
      const cue = FeelingCue(
        activity: '資料作り',
        feeling: Feeling.proud,
        quote: '褒められて嬉しかった',
      );
      final restored = FeelingCue.fromMap(cue.toMap());
      expect(restored?.activity, '資料作り');
      expect(restored?.feeling, Feeling.proud);
      expect(restored?.quote, '褒められて嬉しかった');
    });

    test('知らない感じ方のキーは読み込まない', () {
      expect(
        FeelingCue.fromMap({'activity': 'a', 'feeling': 'x', 'quote': 'q'}),
        isNull,
      );
    });
  });

  group('プロンプト', () {
    test('読み取りの指示は、読み取れないときは返さないことと、根拠の扱いを伝えている', () {
      final text = AiInstructions.feelingReader();
      expect(text, contains('空の配列'));
      expect(text, contains('そのまま抜き出す'));
      expect(text, contains('皮肉や冗談'));
    });

    test('返してよい感じ方を、キーつきで並べる', () {
      final prompt = DiaryPrompts.buildFeelingPrompt(
        feelings: [for (final f in Feeling.values) (f.key, f.label)],
        text: '依頼人: 疲れた',
      );
      expect(prompt, contains('- tired: 疲れた'));
      expect(prompt, contains('【会話】\n依頼人: 疲れた'));
    });
  });
}
