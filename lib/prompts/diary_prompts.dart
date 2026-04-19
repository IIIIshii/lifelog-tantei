// 日記生成プロンプトのテンプレートを組み立てるクラス。
// 生成ルールや口調の指示は ai_instructions.dart に、
// 会話履歴の差し込み方などテンプレート構造はここで管理する。
class DiaryPrompts {
  DiaryPrompts._();

  // 会話履歴から日記生成プロンプトを組み立てる。
  // additionalContext: カスタム質問・思い出しアシストの回答など
  static String buildDiaryPrompt(String conversationHistory,
      {String additionalContext = ''}) {
    final extra = additionalContext.isNotEmpty
        ? '\n\n【参考情報（日記に自然に織り込むこと）】\n$additionalContext'
        : '';
    return '以下が依頼人の証言です：\n$conversationHistory$extra';
  }

  // 既存日記と追記インタビューを統合する日記生成プロンプトを組み立てる。
  // additionalContext: カスタム質問・思い出しアシストの回答など
  static String buildDiaryWithExistingPrompt(
      String existingDiary, String conversationHistory,
      {String additionalContext = ''}) {
    final extra = additionalContext.isNotEmpty
        ? '\n\n【参考情報（日記に自然に織り込むこと）】\n$additionalContext'
        : '';
    return '以下は今日すでに記録された捜査ログです：\n$existingDiary\n\n'
        '以下は追加で得られた証言です：\n$conversationHistory$extra\n\n'
        '二つの内容を自然に統合し、捜査ログとして再記録してください。';
  }
}
