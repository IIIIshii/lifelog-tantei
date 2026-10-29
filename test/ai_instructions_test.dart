import 'package:flutter_test/flutter_test.dart';
import 'package:nikkinext/prompts/ai_instructions.dart';

// 聴取の質問に渡す隠し指示を検証する。
//
// 指示文は変えても画面がエラーにならず、効いているかも気づきにくい。
// 「何を聞かせるか」「何は変えないか」を、文面の要点でここに固定しておく。
void main() {
  const persona = 'あなたはテスト用の探偵です。\nネガティブな言葉・評価は一切使わないこと。\n';

  group('followUpHint（深掘りの質問）', () {
    final hint = AiInstructions.followUpHint(persona);

    test('人格の指示と、終了判定のJSON形式は今までどおり含む', () {
      expect(hint, contains('あなたはテスト用の探偵です'));
      expect(hint, contains('"sufficient": true'));
      expect(hint, contains('"sufficient": false'));
      expect(hint, contains('日々の記録で分かる事実'));
    });

    test('感じ方が自然に出る聞き方を指示し、選択肢や点数は禁じる', () {
      expect(hint, contains('【感じ方の聞き方】'));
      expect(hint, contains('時間の感じ方'));
      expect(hint, contains('選択肢・点数'));
      expect(hint, contains('毎回は聞かず'));
    });

    test('苦手は中立の言い方で聞かせ、評価や決めつけの言葉は禁じる', () {
      expect(hint, contains('エネルギーが減った場面'));
      expect(hint, contains('評価や決めつけの言葉は使わない'));
    });

    test('人格の「ネガティブ禁止」より優先してよい範囲を、中立の聞き方に限っている', () {
      expect(hint, contains('中立の言い方で尋ねる範囲では'));
    });

    test('指針はJSON形式の指示より前にある（出力形式を最後に置く並びを保つ）', () {
      expect(hint.indexOf('【感じ方の聞き方】'), lessThan(hint.indexOf('出力は次のJSON形式')));
    });
  });

  group('感じ方の聞き方を足していないところ', () {
    test('最初の質問は、場面・きっかけ・気持ちを聞く役割のまま', () {
      final hint = AiInstructions.topicQuestionHint(persona);
      expect(hint, contains('場面・きっかけ・そのときの気持ち'));
      expect(hint, isNot(contains('【感じ方の聞き方】')));
    });

    test('日記の本文のルールは、ネガティブ禁止を今のまま残す', () {
      final rules = AiInstructions.diaryWriter('三人称で書く');
      expect(rules, contains('ネガティブな表現・評価は一切含めない'));
    });
  });
}
