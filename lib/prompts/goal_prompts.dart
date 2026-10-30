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
  //
  // progressDigest には追跡中の目標の直近の続き具合（activeGoalsDigest）、
  // pastGoalsDigest には終えた目標の結末（closedGoalsDigest）を渡す。
  // どちらも「前にどう続いたか」を踏まえて、無理のない目標を一緒に考えるための材料で、
  // 空ならブロックごと省く。
  static String buildConsultPrompt(
    String conversationHistory, {
    String targetGoalSummary = '',
    String otherGoalsSummary = '',
    String progressDigest = '',
    String pastGoalsDigest = '',
    String today = '',
  }) {
    final buffer = StringBuffer();

    // Gemini は今日の日付を知らない。渡さないと deadline を学習時点の感覚で
    // 作ってしまい、過去の日付が返る（実機で 2024 年の期限が出た）。
    // 空なら省く（他のブロックと同じ流儀）。
    if (today.isNotEmpty) {
      buffer
        ..writeln('【今日の日付】')
        ..writeln(today)
        ..writeln('deadline は、この日付より後の日付を、ここから数えて決めてください。')
        ..writeln();
    }

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

    if (progressDigest.isNotEmpty) {
      buffer
        ..writeln('【追っている事件の続き具合】')
        ..writeln(progressDigest)
        ..writeln('続いていない項目があっても責めず、無理のない形に見直す材料にしてください。')
        ..writeln();
    }

    if (pastGoalsDigest.isNotEmpty) {
      buffer
        ..writeln('【これまでに終えた事件】')
        ..writeln(pastGoalsDigest)
        ..writeln('なぜ終えたかは分かりません。推測で決めつけず、必要なら依頼人に尋ねてください。')
        ..writeln('同じ狙いで断念した事件があるときは、前より小さく始める形を考えてください。')
        ..writeln();
    }

    buffer.write('以下が依頼人との会話です：\n$conversationHistory');
    return buffer.toString();
  }
}
