// 相談室（目標の壁打ち）で Gemini へ渡すプロンプトのテンプレートを組み立てるクラス。
//
// DiaryPrompts に相乗りさせていないのは、あちらが自身を
// 「日記生成プロンプトのテンプレート」と定義しているため。
// 役割分担は既存のまま：人格は lib/roles/、不変のルールは ai_instructions.dart、
// データの差し込み方（＝このファイル）はプロンプト側に置く。
class GoalPrompts {
  GoalPrompts._();

  // 相談室の会話履歴から、目標を詰めるためのプロンプトを組み立てる。
  //
  // targetGoalSummary には見直す対象の Goal.promptSummary() を渡す。
  // 新しく事件を立てるときは空なので、ブロックごと省く
  // （DiaryPrompts の additionalContext と同じ流儀）。
  //
  // otherGoalsSummary には、ほかに追っている目標の Goal.promptHeadline() を
  // 改行で繋いで渡す。全文ではなく1行ずつにするのは、複数目標ぶんの要約で
  // プロンプトの大半が埋まり、肝心の会話が埋もれるのを避けるため。
  static String buildConsultPrompt(
    String conversationHistory, {
    String targetGoalSummary = '',
    String otherGoalsSummary = '',
  }) {
    final buffer = StringBuffer();

    if (targetGoalSummary.isNotEmpty) {
      buffer
        ..writeln('【見直す事件】')
        ..writeln('以下は依頼人が今追っている目標です。')
        ..writeln('見直したいということなので、これを土台に話を聞いてください。')
        ..writeln(targetGoalSummary)
        ..writeln();
    }

    if (otherGoalsSummary.isNotEmpty) {
      buffer
        ..writeln('【ほかに追っている事件】')
        ..writeln(otherGoalsSummary)
        ..writeln('これらと同じ狙いの事件を新しく立てないでください。')
        ..writeln();
    }

    buffer.write('以下が依頼人との会話です：\n$conversationHistory');
    return buffer.toString();
  }
}
