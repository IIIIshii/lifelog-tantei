import 'package:flutter_test/flutter_test.dart';
import 'package:nikkinext/models/user_settings.dart';

// 独自質問の「どこから加わったか」の保存と読み出しを検証する。
//
// ここを固める理由:
// 出所は設定画面の印にしか使わないので、壊れても画面がエラーにならず
// 「印が出ない／間違った印が出る」という形で静かに間違う。
// とくに、出所を持つ前に登録された質問を「自分で書いた」と断定しないことは、
// あとから見分けが付かなくなる種類の間違いなので機械で確かめておきたい。
void main() {
  group('CustomQuestionSource', () {
    test('保存文字列と往復する', () {
      expect(
        customQuestionSourceFrom(
          customQuestionSourceTo(CustomQuestionSource.self),
        ),
        CustomQuestionSource.self,
      );
      expect(
        customQuestionSourceFrom(
          customQuestionSourceTo(CustomQuestionSource.consult),
        ),
        CustomQuestionSource.consult,
      );
    });

    test('未知の値と欠損は null（自分で書いたと決めつけない）', () {
      expect(customQuestionSourceFrom(null), isNull);
      expect(customQuestionSourceFrom(''), isNull);
      expect(customQuestionSourceFrom('Consult'), isNull);
    });
  });

  group('CustomQuestion', () {
    test('出所を持つ質問は往復する', () {
      const question = CustomQuestion(
        id: 'q1',
        text: '今日いちばん手応えがあったのは？',
        source: CustomQuestionSource.consult,
      );
      final loaded = CustomQuestion.fromMap(question.toMap());
      expect(loaded.id, 'q1');
      expect(loaded.text, '今日いちばん手応えがあったのは？');
      expect(loaded.source, CustomQuestionSource.consult);
    });

    test('出所が無ければキーごと書かない', () {
      const question = CustomQuestion(id: 'q1', text: '質問');
      expect(question.toMap().containsKey('source'), isFalse);
    });

    test('出所を持つ前のドキュメントは null のまま読める', () {
      final loaded = CustomQuestion.fromMap(const {'id': 'q1', 'text': '質問'});
      expect(loaded.source, isNull);
    });

    test('UserSettings 経由でも出所が保たれる', () {
      const settings = UserSettings(
        customQuestions: [
          CustomQuestion(
            id: 'a',
            text: '自分で書いた',
            source: CustomQuestionSource.self,
          ),
          CustomQuestion(
            id: 'b',
            text: '相談室から',
            source: CustomQuestionSource.consult,
          ),
          CustomQuestion(id: 'c', text: '出所不明'),
        ],
      );
      final loaded = UserSettings.fromMap(settings.toMap());
      expect(loaded.customQuestions.map((q) => q.source), [
        CustomQuestionSource.self,
        CustomQuestionSource.consult,
        null,
      ]);
    });
  });
}
