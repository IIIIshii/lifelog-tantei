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

  // 直近期間の事件簿群を解析するプロンプトを組み立てる。
  // entries は (YYYY-MM-DD, データMap) のリストで、日付昇順でも降順でも可。
  // 内部で日付昇順に整形し直し、日記本文と主要回答だけを抜き出して渡す。
  static String buildAnalysisPrompt(
      List<MapEntry<String, Map<String, dynamic>>> entries) {
    final sorted = [...entries]..sort((a, b) => a.key.compareTo(b.key));
    final body = sorted.map((e) {
      final data = e.value;
      final diary = (data['diary'] as String?)?.trim();
      final answers = data['answers'] as Map<String, dynamic>?;
      final numeric = data['numericAnswers'] as Map<String, dynamic>?;

      final parts = <String>['【${e.key}】'];
      if (diary != null && diary.isNotEmpty) {
        parts.add('日記: $diary');
      }
      final answerLine = _formatAnswers(answers, numeric);
      if (answerLine.isNotEmpty) {
        parts.add('回答: $answerLine');
      }
      return parts.join('\n');
    }).join('\n\n');

    return '以下は依頼人の直近${sorted.length}日分の事件簿である。\n\n'
        '$body\n\n'
        '【依頼内容】\n'
        'この記録群を読み返し、以下3節で所見をまとめてください。各節は2〜4文、'
        '全体で400字以内に収めること。見出しは出力に含めること。\n'
        '■所見（全体傾向）\n'
        '■気になる兆候（パターン・繰り返し・変化）\n'
        '■励まし（光っている取り組みへの一言）';
  }

  static String _formatAnswers(
      Map<String, dynamic>? answers, Map<String, dynamic>? numeric) {
    if (answers == null && numeric == null) return '';
    final pairs = <String>[];
    final sleep = numeric?['sleep'];
    if (sleep is num) pairs.add('睡眠${sleep}h');
    void add(String key, String label) {
      final v = answers?[key];
      if (v is String && v.isNotEmpty) pairs.add('$label:$v');
    }
    add('food', '食事');
    add('exercise', '運動');
    add('study', '勉強');
    add('event_what', '出来事');
    add('event_how', '感情');
    add('event_where', '場所');
    return pairs.join(' / ');
  }
}
