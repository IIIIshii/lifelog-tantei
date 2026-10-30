// 日記まわりのプロンプトのテンプレートを組み立てるクラス。
// 生成ルールや口調の指示は ai_instructions.dart に、
// 会話履歴や記録の差し込み方などテンプレート構造はここで管理する。
import '../core/daily_record.dart';
import '../models/record_field.dart';

class DiaryPrompts {
  DiaryPrompts._();

  // 聴取の会話から日記生成プロンプトを組み立てる。
  // recordContext: その日の日々の記録（recordSummary(diaryOnly: true) の結果）
  static String buildDiaryPrompt(
    String conversationHistory, {
    String recordContext = '',
  }) {
    return '以下が依頼人の証言です：\n$conversationHistory'
        '${_recordBlock(recordContext)}';
  }

  // 既存日記と追加の聴取を統合する日記生成プロンプトを組み立てる。
  static String buildDiaryWithExistingPrompt(
    String existingDiary,
    String conversationHistory, {
    String recordContext = '',
  }) {
    return '以下は今日すでに記録された捜査ログです：\n$existingDiary\n\n'
        '以下は追加で得られた証言です：\n$conversationHistory'
        '${_recordBlock(recordContext)}\n\n'
        '二つの内容を自然に統合し、捜査ログとして再記録してください。';
  }

  static String _recordBlock(String recordContext) => recordContext.isEmpty
      ? ''
      : '\n\n【日々の記録（日記に自然に織り込むこと）】\n$recordContext';

  // 話題の候補出しプロンプト。
  //
  // recordContext: その日の記録（recordSummary の結果。空ならまだ記録が無い）
  // recentDiaries: 直近の日記本文。記録が乏しい日に「ふだん何をしている人か」を
  //   掴ませ、思い出すきっかけになる見出しを出させるために渡す
  // coveredTopics: この日に既に話した出来事（同じ候補を出させないため）
  static String buildTopicPrompt({
    required String recordContext,
    List<String> recentDiaries = const [],
    List<String> coveredTopics = const [],
  }) {
    final buffer = StringBuffer()
      ..writeln('【今日の記録】')
      ..writeln(recordContext.isEmpty ? 'まだ記録は無い。' : recordContext);
    if (recentDiaries.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('【最近の日記（参考。今日の事実として扱わないこと）】');
      for (final diary in recentDiaries) {
        buffer.writeln('- $diary');
      }
    }
    if (coveredTopics.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('【既に話した出来事】');
      for (final topic in coveredTopics) {
        buffer.writeln('- $topic');
      }
    }
    buffer
      ..writeln()
      ..write('今日の日記に書く出来事の候補を挙げてください。');
    return buffer.toString();
  }

  // 出来事への最初の質問のプロンプト本文（隠し指示は呼び出し側で前に足す）。
  static String buildTopicQuestionPrompt({
    required String topic,
    required String recordContext,
  }) {
    final record = recordContext.isEmpty ? '' : '\n\n【今日の記録】\n$recordContext';
    return '依頼人が話したい出来事：$topic$record';
  }

  // 話した内容を記録の表へ振り分けるプロンプト。
  //
  // 項目は extractionKey（f0, f1, …）で示し、返答も同じキーで受ける。
  // 型ごとに何を入れればよいかを添えるのは、返させる形（responseSchema）だけでは
  // 「単位」「選択肢の意味」が伝わらないため。
  static String buildRecordExtractionPrompt({
    required List<RecordField> fields,
    required String text,
  }) {
    final buffer = StringBuffer()..writeln('【記録の項目】');
    for (var i = 0; i < fields.length; i++) {
      final field = fields[i];
      final how = switch (field.kind) {
        FieldKind.numeric =>
          field.unit.isEmpty ? '数値' : '数値・単位は${field.unit}',
        FieldKind.yesNo => field.isGoal ? 'はい／いいえ（やったかどうか）' : 'はい／いいえ',
        FieldKind.choice => '選択肢: ${field.choices.join(' / ')}',
        FieldKind.text => '短い文章',
      };
      buffer.writeln('- ${extractionKey(i)}: ${field.promptLabel}（$how）');
    }
    buffer
      ..writeln()
      ..writeln('【依頼人の話】')
      ..write(text.trim());
    return buffer.toString();
  }

  // 直近期間の事件簿群を解析するプロンプトを組み立てる。
  // days は mergeDays の結果（(YYYY-MM-DD, {values, diary})）。日付順は問わない。
  // fields: 値のキー → 記録項目（fieldIndex の結果）。ここに無いキーの値は渡さない。
  // statsBlock: PeriodSummary.toPromptBlock() の結果。平均や増減を AI に暗算させず、
  //   コードで数えた値を渡すためのもの。空ならブロックごと省く。
  static String buildAnalysisPrompt(
    List<MapEntry<String, Map<String, dynamic>>> days, {
    Map<String, RecordField> fields = const {},
    String statsBlock = '',
  }) {
    final sorted = [...days]..sort((a, b) => a.key.compareTo(b.key));
    final body = _formatDays(sorted, fields);
    final stats = statsBlock.isEmpty ? '' : '$statsBlock\n\n';
    final evidence = statsBlock.isEmpty
        ? ''
        : '数字は【集計】の値をそのまま使い、所見の根拠になった日付や値を添えること。\n';

    return '以下は依頼人の直近${sorted.length}日分の事件簿である。\n\n'
        '$body\n\n'
        '$stats'
        '【依頼内容】\n'
        'この記録群を読み返し、以下3節で所見をまとめてください。各節は2〜4文、'
        '全体で400字以内に収めること。見出しは出力に含めること。\n'
        '$evidence'
        '所見の全体を通して、指定の文体・視点に合う軽い冗談（小ボケ）を1つだけ入れること。'
        '記録の数字や事実を曲げず、依頼人の失敗や弱みを笑いにしないこと。'
        '冗談は1か所だけにして、ほかは真面目に書く。\n'
        '■所見（全体傾向）\n'
        '■気になる兆候（パターン・繰り返し・変化）\n'
        '■励まし（光っている取り組みへの一言）';
  }

  // 今日1日と直近の日々を渡して、今日へのコメントプロンプトを組み立てる。
  static String buildDailyCommentPrompt(
    Map<String, dynamic> today,
    List<MapEntry<String, Map<String, dynamic>>> recentDays, {
    Map<String, RecordField> fields = const {},
  }) {
    final todayBody = _formatDay(today, fields);
    final sorted = [...recentDays]..sort((a, b) => a.key.compareTo(b.key));
    final recentBody = _formatDays(sorted, fields);

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

  // 複数日を「【日付】\n日記: ... / 記録: ...」の形に整形する
  static String _formatDays(
    List<MapEntry<String, Map<String, dynamic>>> days,
    Map<String, RecordField> fields,
  ) {
    return days
        .map((e) => '【${e.key}】\n${_formatDay(e.value, fields)}')
        .join('\n\n');
  }

  // 1日分（mergeDays の1要素の値）を「日記: ... / 記録: ...」の行にする。
  static String _formatDay(
    Map<String, dynamic> day,
    Map<String, RecordField> fields,
  ) {
    final parts = <String>[];
    final diary = (day['diary'] as String?)?.trim();
    if (diary != null && diary.isNotEmpty) parts.add('日記: $diary');
    final values = _formatValues(day, fields);
    if (values.isNotEmpty) parts.add('記録: $values');
    return parts.join('\n');
  }

  // 記録の値を「ラベル:値」で並べる。
  //
  // 記録ドキュメントに入っているのは項目 id（custom_<uuid> / goal_<uuid> など）だけで、
  // それが何を記録したものかは記録の型・目標の側にしかない。対応表を呼び出し側から
  // 渡させるのはこのため。
  //
  // 逆に、対応表に無いキーは渡さない。定義ごと消された項目の値が該当し、
  // 何の記録か分からない値を所見の材料にすると、AI が文脈を勝手に補う方向に働くため。
  static String _formatValues(
    Map<String, dynamic> day,
    Map<String, RecordField> fields,
  ) {
    final pairs = <String>[];
    for (final field in fields.values) {
      final text = formatValue(field, valueOf(day, field.id));
      if (text == null) continue;
      pairs.add('${field.promptLabel}:$text');
    }
    return pairs.join(' / ');
  }
}
