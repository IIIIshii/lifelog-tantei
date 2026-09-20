import 'package:uuid/uuid.dart';

// 目標（＝追跡中の事件）と、その達成のための行動項目を表すモデル。
// 保存先は users/{uid}/goals/{goalId}。追跡中の目標は kMaxTrackedGoals 件まで同時に持てる。
//
// UserSettings・SelfAnalysis と分けている理由:
// 記録の設定でも依頼人の属性でもなく、「今どこへ向かっているか」という
// 時間とともに入れ替わるものだから。解決・断念した目標は outcome を付けて
// users/{uid}/goal-archive/{goalId} へ退避し、goals からは消す。
//
// 行動項目（GoalAction）の id は作成時に発行される不変の識別子で、
// 日々の回答の紐付けキー 'goal_<id>' として使う（CustomQuestion と同じ流儀）。
// ラベルを書き換えても並べ替えても id は変わらないため、過去の回答が迷子にならない。
// AI に id を作らせず必ずクライアント側で uuid を振るのは、生成のたびに
// 値が変わる文字列を紐付けキーにすると記録が繋がらなくなるため。

// ──────────────────────────────────────────────────────────────
// 行動項目の記録のしかた
// ──────────────────────────────────────────────────────────────
enum GoalActionType {
  numeric, // 数値で記録する（体重・歩数・時間など）
  check, // 達成／未達の2択で記録する（ジムに行った、など）
}

// 日々の回答マップでの、目標由来のキーにつく接頭辞。
// DiaryPage がこれを見て「数値としても控えるか」を判断する。
const String kGoalAnswerPrefix = 'goal_';

// チェック型の回答に使う固定の選択肢。
// 分析室の達成率もこの文字列との一致で数えるため、表示とデータで同じ定数を使う。
const String kGoalDone = '達成';
const String kGoalNotDone = '未達';

// AI の見立てから受け取る行動項目・独自質問の上限。
// 毎日答える項目が増えるほど記録は続かなくなるので、提案の時点で絞る。
const int kMaxGoalActions = 3;
const int kMaxGoalQuestions = 5;

// 同時に追える事件の数。
// 3件を超えると毎日答える項目が増えるだけでなく、「今日はどれを進めるのか」が
// ホームのカード一画面ぶんで判断できなくなる。
const int kMaxTrackedGoals = 3;

// 全目標を合わせた行動項目の上限。
// 1目標あたり3件（kMaxGoalActions）でも3目標で9問になり、尋問が記録ではなく作業になる。
// 目標が何件あっても、毎日増える質問はここまでに抑える。
const int kMaxTotalGoalActions = 5;

// 旧スキーマ（アクティブな目標が常に1件だった頃）の固定ドキュメントID。
// goals コレクションを読むときだけ特別扱いし、goals/{goalId} へ移す。
const String kLegacyGoalDocId = 'current';

// 保存文字列 → enum。未知の値は check に倒す。
// 2択ならどんな項目でも一応記録は続けられるので、読めない値で
// ドキュメントごと壊すより安全側に寄せる（SelfAnalysis.fromMap と同じ考え方）。
GoalActionType goalActionTypeFrom(String? raw) =>
    raw == 'numeric' ? GoalActionType.numeric : GoalActionType.check;

// enum → 保存文字列。
String goalActionTypeTo(GoalActionType type) =>
    type == GoalActionType.numeric ? 'numeric' : 'check';

// ──────────────────────────────────────────────────────────────
// 追跡を終えた理由
// ──────────────────────────────────────────────────────────────
enum GoalOutcome {
  solved, // 解決した
  abandoned, // 断念した（追うのをやめた）
}

String goalOutcomeTo(GoalOutcome outcome) =>
    outcome == GoalOutcome.solved ? 'solved' : 'abandoned';

// 保存文字列 → enum。読み取れない値・記録の無いものは null を返す。
//
// GoalActionType のように既定値へ倒さないのは、アクティブな目標が1件だった頃の
// goal-archive に「新しい目標を立てたので押し出された」だけのものが入っているため。
// それは解決でも断念でもなく、どちらかへ寄せると嘘の刻印になる。
// 記録が無いことと、記録して0だったことは意味が違う
// （分析室が「—」と「0%」を区別しているのと同じ理由）。
GoalOutcome? goalOutcomeFrom(String? raw) {
  if (raw == 'solved') return GoalOutcome.solved;
  if (raw == 'abandoned') return GoalOutcome.abandoned;
  return null;
}

// 保存値・AI応答から数値を取り出す。
// AI が数字を文字列で返してくることがあるため（responseSchema で number を
// 指定していても保証はされない）、num と String の両方を受ける。
double? _toDouble(Object? raw) {
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw.trim());
  return null;
}

// ──────────────────────────────────────────────────────────────
// 行動項目1件
// ──────────────────────────────────────────────────────────────
class GoalAction {
  final String id; // uuid v4。回答キー 'goal_<id>' の安定IDになる
  final String label; // 「体重」「ジムに行く」など
  final GoalActionType type;
  final String unit; // numeric のときのみ 'kg' 'km' など。check は空文字
  final double? target; // numeric の目標値（任意）

  const GoalAction({
    required this.id,
    required this.label,
    this.type = GoalActionType.check,
    this.unit = '',
    this.target,
  });

  // 項目を後から増やしても既存ドキュメントが読めるよう、欠損はデフォルトで埋める。
  factory GoalAction.fromMap(Map<String, dynamic> map) {
    return GoalAction(
      id: map['id'] as String? ?? '',
      label: map['label'] as String? ?? '',
      type: goalActionTypeFrom(map['type'] as String?),
      unit: map['unit'] as String? ?? '',
      target: _toDouble(map['target']),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'label': label,
    'type': goalActionTypeTo(type),
    'unit': unit,
    'target': target,
  };

  bool get isNumeric => type == GoalActionType.numeric;

  // 日々の回答マップでのキー。分析室もこのキーで値を引く。
  String get answerKey => '$kGoalAnswerPrefix$id';

  // 数値型のときに選択肢を出さずテキスト入力で受けるための質問文。
  // 単位があれば添えて、何を書けばよいかを迷わせない。
  String questionText() {
    if (!isNumeric) return '$label — 今日はどうだった？';
    return unit.isEmpty ? '$label は？（数字で）' : '$label は？（$unit）';
  }

  // AI へ渡す1行。目標の中身をプロンプトに差し込むときに使う。
  String promptLine() {
    final parts = <String>[label];
    if (isNumeric) {
      parts.add(unit.isEmpty ? '数値で記録' : '$unit で記録');
      if (target != null) parts.add('目標 $target$unit');
    } else {
      parts.add('やったかどうかで記録');
    }
    return '- ${parts.join(' / ')}';
  }
}

// ──────────────────────────────────────────────────────────────
// 目標1件
// ──────────────────────────────────────────────────────────────
class Goal {
  final String id; // uuid v4。アーカイブ時のドキュメントIDになる
  final String title; // 「3ヶ月で5kg減らす」など、相談室で具体化した一文
  final String metric; // 達成の判定基準（どうなったら解決なのか）
  final String deadline; // 'YYYY-MM-DD'。期限を決めなかった場合は空文字
  final List<GoalAction> actions; // 日々の記録に差し込む行動項目
  final List<String> suggestedQuestions; // AIが提案した独自質問の候補（未承認のもの）
  final String createdAt; // 'YYYY-MM-DD'。経過日数の起点

  const Goal({
    this.id = '',
    this.title = '',
    this.metric = '',
    this.deadline = '',
    this.actions = const [],
    this.suggestedQuestions = const [],
    this.createdAt = '',
  });

  // 未設定（まだ目標を立てていない）状態を返すファクトリ。
  // FirestoreService はドキュメントが無いときこれを返す。
  factory Goal.defaults() => const Goal();

  // 相談室でAIが返した見立てのマップから目標を組み立てるファクトリ。
  //
  // id（目標・行動項目とも）はここでクライアント側が発行する。
  // AI に作らせると生成のたびに値が変わり、日々の回答と紐付かなくなるため
  // （カスタム質問が index 依存のキーで紐付けを失った経緯と同じ轍を踏まない）。
  // createdAt は呼び出し側から渡す（今日の日付。テストで固定できるようにするため）。
  //
  // AI の出力は信用しすぎない：ラベルの無い行動項目は質問にできないので捨て、
  // 数が多すぎるものは切り詰める（毎日答える項目が増えるほど記録が続かなくなる）。
  factory Goal.fromAiMap(
    Map<String, dynamic> map, {
    required String createdAt,
    int maxActions = kMaxGoalActions,
  }) {
    final actions = <GoalAction>[];
    final rawActions = map['actions'];
    // maxActions は「毎日の記録に残っている枠」。全目標で kMaxTotalGoalActions 件まで
    // という制約は AI 側からは見えないので、受け取った時点でも切っておく。
    if (rawActions is List && maxActions > 0) {
      for (final raw in rawActions) {
        if (raw is! Map) continue;
        final item = Map<String, dynamic>.from(raw);
        final label = (item['label'] as String?)?.trim() ?? '';
        if (label.isEmpty) continue;
        actions.add(
          GoalAction(
            id: const Uuid().v4(),
            label: label,
            type: goalActionTypeFrom(item['type'] as String?),
            unit: (item['unit'] as String?)?.trim() ?? '',
            target: _toDouble(item['target']),
          ),
        );
        if (actions.length >= maxActions) break;
      }
    }

    final questions = <String>[];
    final rawQuestions = map['questions'];
    if (rawQuestions is List) {
      for (final raw in rawQuestions) {
        if (raw is! String) continue;
        final text = raw.trim();
        if (text.isEmpty) continue;
        questions.add(text);
        if (questions.length >= kMaxGoalQuestions) break;
      }
    }

    return Goal(
      id: const Uuid().v4(),
      title: (map['title'] as String?)?.trim() ?? '',
      metric: (map['metric'] as String?)?.trim() ?? '',
      deadline: (map['deadline'] as String?)?.trim() ?? '',
      actions: actions,
      suggestedQuestions: questions,
      createdAt: createdAt,
    );
  }

  // Firestoreのマップからインスタンスを生成するファクトリ。
  // 項目を後から増やしても既存ドキュメントが読めるよう、欠損はデフォルトで埋める。
  factory Goal.fromMap(Map<String, dynamic> map) {
    return Goal(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? '',
      metric: map['metric'] as String? ?? '',
      deadline: map['deadline'] as String? ?? '',
      actions:
          (map['actions'] as List<dynamic>?)
              ?.map(
                (e) => GoalAction.fromMap(Map<String, dynamic>.from(e as Map)),
              )
              .toList() ??
          const [],
      suggestedQuestions:
          (map['suggestedQuestions'] as List<dynamic>?)
              ?.whereType<String>()
              .toList() ??
          const [],
      createdAt: map['createdAt'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'metric': metric,
    'deadline': deadline,
    'actions': actions.map((a) => a.toMap()).toList(),
    'suggestedQuestions': suggestedQuestions,
    'createdAt': createdAt,
  };

  // 一部のフィールドだけ変更した新しいインスタンスを返すメソッド
  Goal copyWith({
    String? id,
    String? title,
    String? metric,
    String? deadline,
    List<GoalAction>? actions,
    List<String>? suggestedQuestions,
    String? createdAt,
  }) {
    return Goal(
      id: id ?? this.id,
      title: title ?? this.title,
      metric: metric ?? this.metric,
      deadline: deadline ?? this.deadline,
      actions: actions ?? this.actions,
      suggestedQuestions: suggestedQuestions ?? this.suggestedQuestions,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  // 追跡中の目標が無い状態か。
  // title を基準にするのは、目標としてホームに出せる最低限がそれだから
  // （行動項目や期限は無くても「何を目指しているか」は成立する）。
  bool get isEmpty => title.trim().isEmpty;

  // 他に追っている目標を1行で表す。
  // 相談室で「同じ狙いの事件を重ねて立てない」ための文脈として AI へ渡す。
  // promptSummary() を使わないのは、2件3件と足すとプロンプトの大半が既存目標で
  // 埋まり、肝心の会話が埋もれるため。
  String promptHeadline() {
    if (isEmpty) return '';
    final extras = <String>[];
    if (deadline.isNotEmpty) extras.add('期限 $deadline');
    if (actions.isNotEmpty) extras.add(actions.map((a) => a.label).join('・'));
    return extras.isEmpty ? '- $title' : '- $title（${extras.join(' / ')}）';
  }

  // 新しく立てた事件が上に来る並び順。事件簿の「直近の事件」と向きを揃える。
  // createdAt が空の古いデータを末尾へ回すのは、着手日の分からないものが
  // 先頭に来ると一番新しい事件のように見えてしまうため。
  // 同着を id で決めているのは、描画のたびに順序が入れ替わって見えるのを防ぐため。
  static int byNewest(Goal a, Goal b) {
    if (a.createdAt.isEmpty != b.createdAt.isEmpty) {
      return a.createdAt.isEmpty ? 1 : -1;
    }
    final byDate = b.createdAt.compareTo(a.createdAt);
    return byDate != 0 ? byDate : a.id.compareTo(b.id);
  }

  // 回答キー → 行動項目のラベル。
  // 保存された回答（goal_<uuid>）を人が読める形に戻すために使う。
  // 日記生成へ渡すときにこれを通さないと、カスタム質問の回答が
  // 「カスタム: はい」としか渡らない現状と同じことになる。
  Map<String, String> answerLabels() => {
    for (final action in actions) action.answerKey: action.label,
  };

  // 数値で記録する行動項目だけを取り出す（分析室のカード分けに使う）
  List<GoalAction> get numericActions =>
      actions.where((a) => a.isNumeric).toList(growable: false);

  // 達成／未達で記録する行動項目だけを取り出す
  List<GoalAction> get checkActions =>
      actions.where((a) => !a.isNumeric).toList(growable: false);

  // 探偵AIのプロンプトへ差し込む事実の要約を返す。
  // 未設定なら空文字を返し、呼び出し側でセクションごと省略できるようにする
  // （SelfAnalysis.promptSummary / DiaryPrompts の additionalContext と同じ流儀）。
  String promptSummary() {
    if (isEmpty) return '';
    final lines = <String>['- 目標: $title'];
    if (metric.isNotEmpty) lines.add('- 達成の基準: $metric');
    if (deadline.isNotEmpty) lines.add('- 期限: $deadline');
    if (actions.isNotEmpty) {
      lines.add('- 日々追っている項目:');
      lines.addAll(actions.map((a) => '  ${a.promptLine()}'));
    }
    return lines.join('\n');
  }
}

// ──────────────────────────────────────────────────────────────
// 追跡を終えた目標1件
//
// goal-archive のドキュメントを読んだ結果。Timestamp を DateTime に直すのは
// 読み出し側（FirestoreService）の仕事で、このファイルは cloud_firestore に依存しない
// ―― モデルを Firestore 無しでテストできる状態に保つため。
// ──────────────────────────────────────────────────────────────
class ArchivedGoal {
  final Goal goal;
  final GoalOutcome? outcome; // 読み取れない・記録の無いものは null
  final DateTime? archivedAt;

  const ArchivedGoal({required this.goal, this.outcome, this.archivedAt});

  // 退避が新しいものが上に来る並び順。archivedAt を持たないものは末尾へ回し、
  // 決め手が無いときは着手日（Goal.byNewest）で並べて描画順を安定させる。
  static int byNewest(ArchivedGoal a, ArchivedGoal b) {
    final at = a.archivedAt;
    final bt = b.archivedAt;
    if (at == null || bt == null) {
      if (at == bt) return Goal.byNewest(a.goal, b.goal);
      return at == null ? 1 : -1;
    }
    final byTime = bt.compareTo(at);
    return byTime != 0 ? byTime : Goal.byNewest(a.goal, b.goal);
  }
}

// ──────────────────────────────────────────────────────────────
// 毎日の記録に出す行動項目の枠
//
// 上限を「1目標あたり」ではなく「全目標の合計」で持つのは、毎朝答える項目の数が
// 記録を続けられるかどうかを決めるから。目標を3件に増やしても質問は3倍にならない。
// ──────────────────────────────────────────────────────────────

// 渡された目標が持つ行動項目の合計。
int totalGoalActions(Iterable<Goal> goals) =>
    goals.fold(0, (sum, goal) => sum + goal.actions.length);

// 新しく採用できる行動項目の残り枠。0未満にはならない。
//
// excludingGoalId に「今まさに見直している目標」の id を渡すと、その目標が
// 今持っている項目は数えない。見直しで項目を入れ替えるときに、自分自身の
// 項目へ枠を食われて1件も選べなくなるのを防ぐため。
int remainingActionSlots(Iterable<Goal> goals, {String? excludingGoalId}) {
  var used = 0;
  for (final goal in goals) {
    // 空文字を除外IDとして扱わない。id を持たない古いデータが
    // まとめて除外されて、枠が実際より多く見えてしまうため。
    if (excludingGoalId != null &&
        excludingGoalId.isNotEmpty &&
        goal.id == excludingGoalId) {
      continue;
    }
    used += goal.actions.length;
  }
  final left = kMaxTotalGoalActions - used;
  return left < 0 ? 0 : left;
}

// 1つの目標で採用できる行動項目の件数。残り枠と1目標あたりの上限の小さい方。
int selectableActionSlots(Iterable<Goal> goals, {String? excludingGoalId}) {
  final left = remainingActionSlots(goals, excludingGoalId: excludingGoalId);
  return left < kMaxGoalActions ? left : kMaxGoalActions;
}

// ──────────────────────────────────────────────────────────────
// 旧スキーマからの移行
// ──────────────────────────────────────────────────────────────

// goals コレクションから読んだ (ドキュメントID, データ) を、そのまま使える目標と、
// 旧スキーマ goals/current から拾った目標に振り分ける。
//
// Firestore を起動せずテストで固められるよう純関数にしている
// （fake_cloud_firestore を入れていないので、切り出さないと検証手段が無い）。
// newId はテストから固定の id を注入するための穴。既定は uuid v4。
//
// タイトルの無い目標を捨てるのは、空のドキュメントが kMaxTrackedGoals の枠を
// ひとつ食って「もう立てられない」状態を作らないため。
({List<Goal> goals, Goal? legacy}) partitionGoalDocs(
  Iterable<MapEntry<String, Map<String, dynamic>>> docs, {
  String Function()? newId,
}) {
  final issue = newId ?? () => const Uuid().v4();
  final goals = <Goal>[];
  Goal? legacy;

  for (final doc in docs) {
    final goal = Goal.fromMap(doc.value);
    if (goal.isEmpty) continue;
    if (doc.key == kLegacyGoalDocId) {
      // 旧ドキュメントは id を持たないことがある（1件しか無いので要らなかった）
      legacy = goal.id.isEmpty ? goal.copyWith(id: issue()) : goal;
      continue;
    }
    // id が欠けていてもドキュメントIDで補える（保存時に必ず一致させているため）
    goals.add(goal.id.isEmpty ? goal.copyWith(id: doc.key) : goal);
  }

  return (goals: goals, legacy: legacy);
}

// 見立て直した目標の行動項目に、見直す前と同じものがあれば元の id を引き継ぐ。
//
// Goal.fromAiMap は毎回新しい uuid を振るので、見直しで同じ「体重」が再提案されても
// そのままでは 'goal_<id>' が変わり、これまでの記録と繋がらなくなる。
// ラベルだけで一致させず型も見るのは、同じ「体重」でも check から numeric へ
// 変わったら記録の意味が変わり、繋げると分析室の値が混ざるため。
// 同じラベル・型が複数あるときは先に現れたものから配り、ひとつの id を二重に使わない。
Goal carryOverActionIds(Goal draft, Goal? previous) {
  if (previous == null || previous.actions.isEmpty) return draft;

  final pool = <String, List<String>>{};
  for (final action in previous.actions) {
    pool.putIfAbsent(_carryKey(action), () => <String>[]).add(action.id);
  }

  final carried = <GoalAction>[];
  for (final action in draft.actions) {
    final ids = pool[_carryKey(action)];
    carried.add(
      ids == null || ids.isEmpty
          ? action
          : GoalAction(
              id: ids.removeAt(0),
              label: action.label,
              type: action.type,
              unit: action.unit,
              target: action.target,
            ),
    );
  }
  return draft.copyWith(actions: carried);
}

// 引き継ぎの一致判定に使うキー。ラベルに現れない NUL で型と繋ぐ。
String _carryKey(GoalAction action) =>
    '${goalActionTypeTo(action.type)}\u0000${action.label}';
