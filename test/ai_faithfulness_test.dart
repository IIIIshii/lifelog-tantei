import 'package:flutter_test/flutter_test.dart';
import 'package:nikkinext/prompts/ai_instructions.dart';
import 'package:nikkinext/prompts/diary_prompts.dart';

// 所見と日記が、記録や発言にないことを書き足さないための指示を検証する。
//
// AI の出力そのものはここでは確かめられない。指示に必要な言葉が残っていることを
// 確かめて、後から書き換えたときに黙って落ちないようにする。
void main() {
  group('所見（analyst）', () {
    final text = AiInstructions.analyst('硬質な三人称');

    test('増減の理由が記録に無いときは、理由を推測せず「記録からは分からない」と書かせる', () {
      expect(text, contains('理由を推測して書かず'));
      expect(text, contains('理由は記録からは分からない'));
    });

    test('同じ時期にあっただけの出来事を、原因として結びつけさせない', () {
      expect(text, contains('原因として結びつけない'));
    });
  });

  group('日記（diaryWriter）', () {
    test('依頼人が語っていない気持ち・考え・因果を書き足させない', () {
      final text = AiInstructions.diaryWriter('硬質な三人称');
      expect(text, contains('語っていない気持ち・考え・因果'));
      expect(text, contains('書かずに省く'));
    });
  });

  group('所見のプロンプト', () {
    test('小ボケを1つだけ入れる指示を含む', () {
      final prompt = DiaryPrompts.buildAnalysisPrompt(const []);
      expect(prompt, contains('軽い冗談（小ボケ）を1つだけ'));
      // 事実や弱みを笑いにしない歯止めも一緒に伝えている
      expect(prompt, contains('依頼人の失敗や弱みを笑いにしない'));
      expect('小ボケ'.allMatches(prompt).length, 1);
    });
  });
}
