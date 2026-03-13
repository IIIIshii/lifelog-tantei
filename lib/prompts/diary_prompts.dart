// Geminiへ投げるプロンプト文字列を一元管理するクラス。ロール変更はここだけ触ればOK
class DiaryPrompts {
  /// 今日の出来事についての最初の質問を生成するプロンプト
  static String firstQuestion() {
    return '今日の日記を書くためのインタビューをします。'
        'ユーザーに今日の出来事について、親しみやすく短い質問を1つだけしてください。';
  }

  /// 会話の流れを受けて深堀り質問を生成するプロンプト
  static String followUp(String conversationHistory) {
    return '以下は日記インタビューの会話です:\n$conversationHistory\n\n'
        'ユーザーの回答に対して、もう少し詳しく聞く自然な深堀り質問を1つだけしてください。';
  }

  /// カスタム質問について深堀りするプロンプト
  static String customFollowUp(String question, String conversationHistory) {
    return '以下は日記インタビューの会話です:\n$conversationHistory\n\n'
        'ユーザーが「$question」という質問に答えました。'
        'この回答に対して自然な深堀り質問を1つだけしてください。';
  }

  /// 会話全体から日記を生成するプロンプト
  static String generateDiary(String conversationHistory) {
    return '以下の会話を元に、ユーザーの視点で100〜300字の自然な日記を生成してください。\n\n'
        '$conversationHistory';
  }
}
