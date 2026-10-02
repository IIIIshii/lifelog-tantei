// 目標の進捗を、保存済みの事件簿エントリ群から算出する純粋関数群。
//
// なぜ純粋関数として切り出すか：
// 進捗は「答えた日だけを母数にする」「記録の無い日と未達の日は違う」といった
// 取り違えやすい数え方の上に成り立っている。UI から独立させておけば
// 単体テストで検証でき、ホームのハイライトと分析室で同じ定義を共有できる。
//
// 引数の entries には FirestoreService.getRecentEntries の戻り値
// （(YYYY-MM-DD, ドキュメントのMap) のリスト）をそのまま渡せる。順序は問わない。
// answerKey には GoalAction.answerKey（'goal_<id>'）を渡すこと。

import '../models/goal.dart';

/// エントリ1件から、指定した行動項目への回答文字列を取り出す。
/// 未回答・空文字・スキップした日、エントリそのものが無い日は null を返す。
///
/// 記録一覧が「その日に何と答えたか」を出すのにも使うので公開している
/// （エントリの Map の形を知っているのはこのファイルだけに留めたい）。
String? answerFor(Map<String, dynamic>? entry, String answerKey) {
  final answers = entry?['answers'] as Map<String, dynamic>?;
  final value = answers?[answerKey];
  return value is String && value.isNotEmpty ? value : null;
}

/// エントリ1件から、指定した行動項目の数値を取り出す。
/// 数値として控えられなかった回答（パースに失敗した自由記述）は null を返す。
double? numericFor(Map<String, dynamic>? entry, String answerKey) {
  final numeric = entry?['numericAnswers'] as Map<String, dynamic>?;
  final value = numeric?[answerKey];
  return value is num ? value.toDouble() : null;
}

/// チェック型の行動項目の「答えた日数」と「達成した日数」。
///
/// 母数は「その項目に答えた日」だけで、答えなかった日・スキップした日は数えない。
/// 記録を始める前の日まで未達に数えると、続けるほど率が下がって見えてしまうため。
///
/// 率ではなく件数も返すのは、表示側で母数を添えられるようにするため
/// （率だけだと「1日だけ答えて達成」と「14日続けて達成」がどちらも100%になる）。
({int answered, int done}) checkCounts(
  List<MapEntry<String, Map<String, dynamic>>> entries,
  String answerKey,
) {
  var answered = 0;
  var done = 0;
  for (final entry in entries) {
    final answer = answerFor(entry.value, answerKey);
    // 想定外の文字列（旧データや手動編集）は母数にも分子にも入れない
    if (answer != kGoalDone && answer != kGoalNotDone) continue;
    answered++;
    if (answer == kGoalDone) done++;
  }
  return (answered: answered, done: done);
}

/// チェック型の行動項目の達成率（0.0〜1.0）。一度も答えていなければ null。
/// 数え方は checkCounts と同じ（答えた日だけを母数にする）。
double? checkRate(
  List<MapEntry<String, Map<String, dynamic>>> entries,
  String answerKey,
) {
  final counts = checkCounts(entries, answerKey);
  if (counts.answered == 0) return null;
  return counts.done / counts.answered;
}

/// 数値型の行動項目の最新値。記録が無ければ null。
///
/// entries の並び順に依存しないよう、日付キーの大きい方を採る
/// （'YYYY-MM-DD' は辞書順と時系列順が一致する）。
double? latestNumeric(
  List<MapEntry<String, Map<String, dynamic>>> entries,
  String answerKey,
) {
  String? latestDate;
  double? latestValue;
  for (final entry in entries) {
    final value = numericFor(entry.value, answerKey);
    if (value == null) continue;
    if (latestDate == null || entry.key.compareTo(latestDate) > 0) {
      latestDate = entry.key;
      latestValue = value;
    }
  }
  return latestValue;
}

/// 目標を立てた日から today までの経過日数。立てた当日は 0。
/// createdAt が空・不正な形式なら 0 を返す（表示を壊さない側に倒す）。
int daysSince(String createdAt, DateTime today) {
  final start = _parseDateKey(createdAt);
  if (start == null) return 0;
  final end = DateTime.utc(today.year, today.month, today.day);
  final days = end.difference(start).inDays;
  return days < 0 ? 0 : days;
}

/// 'YYYY-MM-DD' を UTC の DateTime にする。解釈できなければ null。
///
/// UTC で作るのは、差分を取るときに夏時間の影響を受けないようにするため
/// （ローカル時刻同士だと DST をまたぐ差が 23h / 25h になり inDays が1ずれる）。
DateTime? _parseDateKey(String key) {
  final parts = key.split('-');
  if (parts.length != 3) return null;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) return null;
  return DateTime.utc(year, month, day);
}

/// その日のエントリに、指定した目標の行動項目への回答が1つでもあるか。
///
/// 接頭辞ではなく、その目標が持つ answerKey の集合で判定する。
/// 目標が複数あると 'goal_' 接頭辞だけでは「どの目標を記録したのか」が分からず、
/// 1件答えただけで全部が記録済みに見えてしまうため。
///
/// 行動項目を持たない目標は常に false。答えるものが無いのに「記録済み」と出すと、
/// 何をしたのか分からないバッジになる（表示側もこの場合はバッジを出さない）。
bool hasAnswerForGoal(Map<String, dynamic>? entry, Goal goal) {
  if (entry == null || goal.actions.isEmpty) return false;
  return goal.actions.any(
    (action) => answerFor(entry, action.answerKey) != null,
  );
}

/// その日に記録済みの目標 id の集合。
/// ホームと相談室ハブが同じ判定を共有できるよう、集合の形でまとめて返す。
///
/// 引数は FirestoreService.getGoalEntriesOn の戻り値（目標 id → その日のエントリ）。
/// 目標ごとに別のエントリを見るのは、日々の記録が目標のドキュメント配下
/// （goals/{goalId}/entries/{date}）へ移り、日記のエントリには入らなくなったため。
Set<String> goalsRecordedIn(
  Map<String, Map<String, dynamic>?> entryByGoalId,
  Iterable<Goal> goals,
) => {
  for (final goal in goals)
    if (hasAnswerForGoal(entryByGoalId[goal.id], goal)) goal.id,
};

/// 「着手から n 日 / 期限 YYYY-MM-DD」の1行。
///
/// createdAt を持たない古い目標では経過を出さない ―― 着手日が分からないものを
/// 「着手から0日」と書くと、今日始めたように見えてしまう。
///
/// 相談室ハブ・分析室・記録一覧が同じ文面を出すため、ここに1本化している
/// （以前は consult_hub_page と analytics_page がほぼ同じ実装を別々に持っていた）。
String elapsedLabel(Goal goal, DateTime today) {
  final deadline = goal.deadline.isEmpty ? '' : ' / 期限 ${goal.deadline}';
  if (goal.createdAt.isEmpty) {
    return deadline.isEmpty ? '着手日は記録されていない' : '期限 ${goal.deadline}';
  }
  return '着手から${daysSince(goal.createdAt, today)}日$deadline';
}

/// 日記のエントリと目標のエントリを、AI へ渡すために日付で1枚へ重ねる。
///
/// 保存はしない。分離したことで目標の回答が日記のエントリに入らなくなり、
/// そのまま所見へ渡すと「何を追っていて、どう進んだか」が材料から静かに落ちる。
/// 落ちたことは出力を読んでも気づけないので、渡す直前にここで合わせる。
///
/// 日付は和集合。目標だけ答えた日（日記を書かなかった日）も材料に含める。
/// 元の Map は書き換えず、answers / numericAnswers を新しい Map に写して返す
/// ―― 引数は画面が保持しているキャッシュで、破壊すると次の描画に影響する。
///
/// キーの衝突は起きない（目標由来は `goal_<uuid>`、日記由来は固定キーか `custom_<uuid>`）。
List<MapEntry<String, Map<String, dynamic>>> mergeGoalAnswers(
  List<MapEntry<String, Map<String, dynamic>>> diaryEntries,
  Map<String, List<MapEntry<String, Map<String, dynamic>>>> goalEntriesByGoalId,
) {
  final merged = <String, Map<String, dynamic>>{};

  void absorb(String date, Map<String, dynamic> source) {
    final target = merged.putIfAbsent(date, () => <String, dynamic>{});
    for (final field in ['answers', 'numericAnswers']) {
      final incoming = source[field] as Map<String, dynamic>?;
      if (incoming == null || incoming.isEmpty) continue;
      final existing = target[field] as Map<String, dynamic>?;
      target[field] = <String, dynamic>{...?existing, ...incoming};
    }
    // 日記本文・モードはそのまま持ち越す（目標側には無い）
    for (final field in ['diary', 'diaryMode']) {
      final value = source[field];
      if (value != null) target[field] = value;
    }
  }

  for (final entry in diaryEntries) {
    absorb(entry.key, entry.value);
  }
  for (final entries in goalEntriesByGoalId.values) {
    for (final entry in entries) {
      absorb(entry.key, entry.value);
    }
  }

  return [for (final entry in merged.entries) MapEntry(entry.key, entry.value)];
}
