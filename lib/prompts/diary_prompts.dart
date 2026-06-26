// 日記生成プロンプトのテンプレートを組み立てるクラス。
// 生成ルールや口調の指示は ai_instructions.dart に、
// 会話履歴の差し込み方などテンプレート構造はここで管理する。
class DiaryPrompts {
  DiaryPrompts._();

  // 会話履歴から日記生成プロンプトを組み立てる。
  // additionalContext: カスタム質問・思い出しアシストの回答など
  static String buildDiaryPrompt(
    String conversationHistory, {
    String additionalContext = '',
  }) {
    final extra = additionalContext.isNotEmpty
        ? '\n\n【参考情報（日記に自然に織り込むこと）】\n$additionalContext'
        : '';
    return '以下が依頼人の証言です：\n$conversationHistory$extra';
  }

  // 既存日記と追記インタビューを統合する日記生成プロンプトを組み立てる。
  // additionalContext: カスタム質問・思い出しアシストの回答など
  static String buildDiaryWithExistingPrompt(
    String existingDiary,
    String conversationHistory, {
    String additionalContext = '',
  }) {
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
    List<MapEntry<String, Map<String, dynamic>>> entries,
  ) {
    final sorted = [...entries]..sort((a, b) => a.key.compareTo(b.key));
    final body = _formatEntries(sorted); // ← 切り出したメソッドを呼ぶ

    return '以下は依頼人の直近${sorted.length}日分の事件簿である。\n\n'
        '$body\n\n'
        '【依頼内容】\n'
        'この記録群を読み返し、以下3節で所見をまとめてください。各節は2〜4文、'
        '全体で400字以内に収めること。見出しは出力に含めること。\n'
        '■所見（全体傾向）\n'
        '■気になる兆候（パターン・繰り返し・変化）\n'
        '■励まし（光っている取り組みへの一言）';
  }

  // 複数エントリを「【日付】日記: ... / 回答: ...」形式の文字列に整形する
  static String _formatEntries(
    List<MapEntry<String, Map<String, dynamic>>> entries,
  ) {
    return entries
        .map((e) {
          final data = e.value;
          final diary = (data['diary'] as String?)?.trim();
          final answers = data['answers'] as Map<String, dynamic>?;
          final numeric = data['numericAnswers'] as Map<String, dynamic>?;

          final parts = <String>['【${e.key}】'];
          if (diary != null && diary.isNotEmpty) parts.add('日記: $diary');
          final answerLine = _formatAnswers(answers, numeric);
          if (answerLine.isNotEmpty) parts.add('回答: $answerLine');
          return parts.join('\n');
        })
        .join('\n\n');
  }

  static String _formatAnswers(
    Map<String, dynamic>? answers,
    Map<String, dynamic>? numeric,
  ) {
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

  // 今日1日のエントリと直近14日分を渡して、今日へのコメントプロンプトを組み立てる。
  static String buildDailyCommentPrompt(
    Map<String, dynamic> todayEntry,
    List<MapEntry<String, Map<String, dynamic>>> recentEntries,
  ) {
    // 今日のデータを整形
    final diary = (todayEntry['diary'] as String?)?.trim();
    final answers = todayEntry['answers'] as Map<String, dynamic>?;
    final numeric = todayEntry['numericAnswers'] as Map<String, dynamic>?;

    final todayParts = <String>[];
    if (diary != null && diary.isNotEmpty) todayParts.add('日記: $diary');
    final answerLine = _formatAnswers(answers, numeric);
    if (answerLine.isNotEmpty) todayParts.add('回答: $answerLine');
    final todayBody = todayParts.join('\n');

    // 直近14日分を整形
    final sorted = [...recentEntries]..sort((a, b) => a.key.compareTo(b.key));
    final recentBody = _formatEntries(sorted);

    return '以下は依頼人の今日の記録である。\n\n'
        '$todayBody\n\n'
        '以下は依頼人の直近${sorted.length}日分の事件簿である（比較参考用）。\n\n'
        '$recentBody\n\n'
        '【依頼内容】\n'
        '今日の記録を読み、以下3節でコメントをまとめてください。各節は1〜2文、'
        '全体で200字以内に収めること。見出しは出力に含めること。\n'
        '■今日の要約\n'
        '■気になった点（直近の傾向との違い・変化）\n'
        '■探偵からの一言';
  }
}
