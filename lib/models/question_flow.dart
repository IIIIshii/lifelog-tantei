import 'user_settings.dart';

enum QuestionType { fixed, aiFollowUp, addendum }

class Question {
  final String text; // aiFollowUp のときは空文字（実行時に生成）
  final QuestionType type;

  const Question({required this.text, this.type = QuestionType.fixed});
}

class QuestionFlow {
  static List<Question> build(UserSettings settings) {
    final questions = <Question>[];

    if (settings.recordEvent) {
      questions.addAll(const [
        Question(text: 'いつのことですか？'),
        Question(text: 'どこで起きた出来事ですか？'),
        Question(text: '誰と一緒でしたか？（一人だった場合はそのまま教えてください）'),
        Question(text: '何をしましたか？'),
        Question(text: 'どうでしたか？感想や気持ちを教えてください。'),
      ]);
    }

    if (settings.recallAssist) {
      questions.addAll(const [
        Question(text: '午前中は何をしていましたか？'),
        Question(text: '午後は何をしていましたか？'),
        Question(text: '夜は何をしていましたか？'),
      ]);
    }

    if (settings.recordSleep) {
      questions.add(const Question(text: '昨夜は何時間くらい眠れましたか？'));
    }

    if (settings.recordFood) {
      questions.add(const Question(text: '今日食べたものを教えてください。'));
    }

    if (settings.recordExercise) {
      questions.add(const Question(text: '今日運動はしましたか？'));
    }

    if (settings.recordStudy) {
      questions.add(const Question(text: '今日勉強した内容を教えてください。'));
    }

    for (final q in settings.customQuestions) {
      questions.add(Question(text: q));
    }

    // AIによる追加質問（テキストは実行時に生成）
    questions.add(const Question(text: '', type: QuestionType.aiFollowUp));

    // 追記
    questions.add(const Question(
      text: '最後に、追記したいことはありますか？（なければ「なし」と入力してください）',
      type: QuestionType.addendum,
    ));

    return questions;
  }
}
