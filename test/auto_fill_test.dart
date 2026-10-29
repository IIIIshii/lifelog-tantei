import 'package:flutter_test/flutter_test.dart';
import 'package:nikkinext/core/auto_fill.dart';
import 'package:nikkinext/core/daily_record.dart';
import 'package:nikkinext/models/record_field.dart';
import 'package:nikkinext/prompts/ai_instructions.dart';

// 聴取の会話から記録の表を自動で埋める判断を検証する。
//
// 自動で入れた値が間違っていたり、利用者が表に書いた値を上書きしたりすると、
// 記録への信頼が下がる。「空欄だけを埋める」「印で区別する」「何を入れたか見せる」を固める。
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
  const memo = RecordField(id: 'memo', label: '午前にしたこと');
  const fields = [sleep, exercise, mood, memo];

  group('autoFilledIds', () {
    test('印があり、値も入っている項目だけを返す', () {
      final record = {
        'values': {'sleep': 6.5, 'exercise': true},
        kAutoFilledKey: ['sleep', 'exercise'],
      };
      expect(autoFilledIds(record), ['sleep', 'exercise']);
    });

    test('利用者が値を消した項目は、印が残っていても含めない', () {
      final record = {
        'values': {'sleep': 6.5},
        kAutoFilledKey: ['sleep', 'exercise'], // exercise の値は消えている
      };
      expect(autoFilledIds(record), ['sleep']);
    });

    test('空文字に戻された項目も、値が無いものとして含めない', () {
      final record = {
        'values': {'memo': ''},
        kAutoFilledKey: ['memo'],
      };
      expect(autoFilledIds(record), isEmpty);
    });

    test('印が無い・記録が無い・形が違うときは空', () {
      expect(autoFilledIds(null), isEmpty);
      expect(
        autoFilledIds({
          'values': {'sleep': 7},
        }),
        isEmpty,
      );
      expect(autoFilledIds({kAutoFilledKey: 'sleep'}), isEmpty);
      expect(
        autoFilledIds({
          'values': {'sleep': 7},
          kAutoFilledKey: [1, null, 'sleep'],
        }),
        ['sleep'],
      );
    });
  });

  group('autoRejectedIds', () {
    test('取り消した項目の id を集める', () {
      expect(
        autoRejectedIds({
          kAutoRejectedKey: ['sleep', 'mood', 'sleep'],
        }),
        {'sleep', 'mood'},
      );
    });

    test('無い・形が違う・文字列でない要素は無視する', () {
      expect(autoRejectedIds(null), isEmpty);
      expect(autoRejectedIds({'values': {}}), isEmpty);
      expect(autoRejectedIds({kAutoRejectedKey: 'sleep'}), isEmpty);
      expect(
        autoRejectedIds({
          kAutoRejectedKey: [1, null, 'mood'],
        }),
        {'mood'},
      );
    });
  });

  group('autoFillTargets（空欄だけを埋める）', () {
    test('すでに値がある項目は、AI が別の値を読み取っても触らない', () {
      final proposals = proposalsFromExtraction(
        fields,
        {'f0': 6.5, 'f2': '良い'},
        {'sleep': null, 'mood': 'ふつう'}, // 気分は利用者が入れ済み
      );
      final targets = autoFillTargets(proposals);
      expect(targets.map((p) => p.field.id), ['sleep']);
    });

    test('空欄の項目は、読み取れたものをすべて対象にする', () {
      final proposals = proposalsFromExtraction(fields, {
        'f0': 7,
        'f1': false,
        'f3': 'カフェで読書',
      }, const {});
      expect(autoFillTargets(proposals).length, 3);
    });

    test('値が空文字の項目も、空欄として埋めてよい', () {
      final proposals = proposalsFromExtraction(
        fields,
        {'f3': 'カフェで読書'},
        {'memo': ''},
      );
      expect(autoFillTargets(proposals).map((p) => p.field.id), ['memo']);
    });

    test('利用者が取り消した項目は、空欄でも入れ直さない（日記を作り直したとき）', () {
      final proposals = proposalsFromExtraction(
        fields,
        {'f0': 6.5, 'f1': true},
        const {}, // 取り消したので、どちらも空欄に戻っている
      );
      final targets = autoFillTargets(proposals, rejected: {'sleep'});
      expect(targets.map((p) => p.field.id), ['exercise']);
    });

    test('読み取れなかった項目・型の合わない値は、対象にならない', () {
      final proposals = proposalsFromExtraction(
        fields,
        {'f1': 'はい', 'f2': '最高'}, // 真偽値ではない文字列、選択肢に無い値
        const {},
      );
      expect(autoFillTargets(proposals), isEmpty);
    });
  });

  group('transcriptForExtraction', () {
    test('探偵と依頼人の発言に名前を付けて並べる', () {
      final text = transcriptForExtraction([
        (role: 'ai', text: '昨夜はどうだった？'),
        (role: 'user', text: '6時間半くらい寝た'),
      ]);
      expect(text, '探偵: 昨夜はどうだった？\n依頼人: 6時間半くらい寝た');
    });

    test('空の発言と、会話以外の行は読ませない', () {
      final text = transcriptForExtraction([
        (role: 'user', text: '  '),
        (role: 'diary', text: 'できあがった日記'),
        (role: 'user', text: '走った'),
      ]);
      expect(text, '依頼人: 走った');
    });

    test('依頼人の発言が1つも無ければ、読み取る材料が無いので空', () {
      expect(transcriptForExtraction([(role: 'ai', text: '今日はどんな日だった？')]), '');
      expect(transcriptForExtraction(const []), '');
    });

    test('読み取りの指示は、依頼人の発言だけを事実として読むと伝えている', () {
      expect(AiInstructions.recordExtractor(), contains('依頼人の発言だけを事実として読む'));
    });
  });

  group('autoFillSummary', () {
    List<RecordProposal> applied(Map<String, Object> raw) =>
        autoFillTargets(proposalsFromExtraction(fields, raw, const {}));

    test('入れた項目を「名前 値」で並べる（単位・はい／いいえも表示用に直す）', () {
      final summary = autoFillSummary(applied({'f0': 6.5, 'f1': true}));
      expect(summary, '睡眠時間 6.5時間 / 運動した はい');
    });

    test('3件を超えたら、残りは件数で示す', () {
      final summary = autoFillSummary(
        applied({'f0': 7, 'f1': false, 'f2': '良い', 'f3': 'カフェ'}),
      );
      expect(summary, '睡眠時間 7時間 / 運動した いいえ / 今日の気分 良い ほか1件');
    });

    test('何も入れていなければ空文字', () {
      expect(autoFillSummary(const []), '');
    });
  });
}
