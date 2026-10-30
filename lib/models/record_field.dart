import 'goal.dart';

// ──────────────────────────────────────────────────────────────
// 日々の記録の「型」（記録項目の定義）
//
// 睡眠時間・その日の気分・午前にしたこと・カスタム項目・目標の行動項目を、
// すべてこの1つの形で扱う。日々の記録の表（RecordSheetPage）は型ごとに
// 入力部品を出し分けるだけで、項目がどこから来たかを知らずに済む。
//
// 値そのものは users/{uid}/records/{YYYY-MM-DD} の values に
// 「項目 id → 値」で入る（daily_record.dart を参照）。
//
// 定義の置き場所は2つある:
// - 生活の記録・カスタム項目 … users/{uid}/settings/fields の items[]
// - 目標の行動項目           … goals/{goalId} の actions[]（GoalAction）
// 目標の項目を設定側へ写さないのは、目標を閉じたときに項目も一緒に外れてほしいため。
// 写すと「目標は閉じたのに毎日の表に項目が残る」ずれを同期で防ぐことになる。
// 目標側の項目は RecordField.fromGoalAction でこの形に読み替える。
// ──────────────────────────────────────────────────────────────

/// 記録のしかた。入力部品・表示・集計の出し分けはすべてこれで決まる。
enum FieldKind {
  numeric, // 数値（睡眠時間・体重・歩数など）
  yesNo, // はい／いいえ（運動した、など）
  choice, // 選択肢から1つ（気分など）
  text, // 短い自由記述（午前にしたこと、など）
}

// 保存文字列 → enum。未知の値は text に倒す。
// 自由記述ならどんな値でも表示だけはできるので、読めない値で項目ごと壊すより安全側。
FieldKind fieldKindFrom(String? raw) => switch (raw) {
  'numeric' => FieldKind.numeric,
  'yesNo' => FieldKind.yesNo,
  'choice' => FieldKind.choice,
  _ => FieldKind.text,
};

String fieldKindTo(FieldKind kind) => switch (kind) {
  FieldKind.numeric => 'numeric',
  FieldKind.yesNo => 'yesNo',
  FieldKind.choice => 'choice',
  FieldKind.text => 'text',
};

/// 設定画面・項目の編集で見せる型の名前。
String fieldKindLabel(FieldKind kind) => switch (kind) {
  FieldKind.numeric => '数値',
  FieldKind.yesNo => 'はい／いいえ',
  FieldKind.choice => '選択肢',
  FieldKind.text => 'テキスト',
};

/// 項目がどこから加わったか。設定画面で見分けるために持つ。
enum FieldSource {
  preset, // 最初から用意されている項目（睡眠時間など）
  self, // 設定画面で自分で足した
  consult, // 相談室で探偵の提案を採用した
  health, // 端末（Health Connect）と連携して足した
}

// 保存文字列 → enum。記録の無いもの・読めない値は null。
//
// 既定値へ倒さないのは、出所の分からないものを「自分で足した」と断定しないため
// （GoalOutcome と同じ考え方で、分からないものには印を出さない）。
FieldSource? fieldSourceFrom(String? raw) => switch (raw) {
  'preset' => FieldSource.preset,
  'self' => FieldSource.self,
  'consult' => FieldSource.consult,
  'health' => FieldSource.health,
  _ => null,
};

String fieldSourceTo(FieldSource source) => switch (source) {
  FieldSource.preset => 'preset',
  FieldSource.self => 'self',
  FieldSource.consult => 'consult',
  FieldSource.health => 'health',
};

/// カスタム項目の id につく接頭辞。目標の項目（'goal_'）と同じ役割で、
/// 値のキーを見ただけで出所が分かるようにする。
const String kCustomFieldPrefix = 'custom_';

/// 端末から読む項目の id につく接頭辞（`health_steps` など）。
/// uuid ではなく固定の名前にするのは、同じ種類（歩数など）を何度連携し直しても
/// 同じ項目に値が入ってほしいため。どの種類かは core/health_daily.dart の一覧で決まる。
const String kHealthFieldPrefix = 'health_';

// ── 最初から用意されている項目の id ───────────────────────────
// 分析室のサマリー（平均睡眠・気分の分布など）がこの id で値を引く。
const String kSleepFieldId = 'sleep';
const String kMoodFieldId = 'mood';
const String kExerciseFieldId = 'exercise';
const String kStudyFieldId = 'study';
const String kFoodFieldId = 'food';
const String kMorningFieldId = 'morning';
const String kAfternoonFieldId = 'afternoon';
const String kEveningFieldId = 'evening';

/// 気分の選択肢。分析室の分布はこの順で並ぶ。
const List<String> kMoodChoices = ['とても良い', '良い', 'ふつう', 'いまいち', 'よくない'];

class RecordField {
  /// 全曜日（1=月〜7=日。DateTime.weekday と同じ番号）
  static const List<int> allWeekdays = [1, 2, 3, 4, 5, 6, 7];

  /// 値のキー。プリセットは `sleep` などの固定値、カスタムは `custom_<uuid>`、
  /// 目標の項目は `goal_<uuid>`（GoalAction.answerKey）。
  /// 並べ替え・名前の変更をしても変わらない（値との紐付けが切れないように）。
  final String id;

  final String label;
  final FieldKind kind;

  /// numeric の単位（「時間」「kg」など）。それ以外は空文字。
  final String unit;

  /// numeric の目標値。目標の項目だけが持つ（グラフの破線に使う）。
  final double? target;

  /// choice の選択肢。それ以外は空。
  final List<String> choices;

  /// 表に出す曜日。毎日ではない項目（週末だけ聞く、など）のため。
  final List<int> weekdays;

  final FieldSource? source;

  /// 日記の材料として探偵に渡すか。
  /// 体重のように、事実としては残したいが本文には出したくない項目があるため。
  final bool useInDiary;

  /// AI に値を渡すか。オフの項目は、日記・話題の候補・所見・今日のコメントの
  /// どれにも値を渡さない（記録と表示には残る）。
  /// 血圧・血糖・月経のように、記録はしたいが外へは出したくない項目があるため。
  /// useInDiary より強く、オフなら日記にも使わない。
  final bool shareWithAi;

  /// 今使っているか。使わなくなった項目は消さずにここを false にする。
  /// 消すと、過去の値が「何を記録したものか」分からなくなるため
  /// （以前、消したカスタム質問の回答を分析室が読めなくなっていた）。
  final bool active;

  /// 目標の項目のときだけ、その目標の id とタイトル。保存はしない。
  final String? goalId;
  final String? goalTitle;

  const RecordField({
    required this.id,
    required this.label,
    this.kind = FieldKind.text,
    this.unit = '',
    this.target,
    this.choices = const [],
    this.weekdays = allWeekdays,
    this.source,
    this.useInDiary = true,
    this.shareWithAi = true,
    this.active = true,
    this.goalId,
    this.goalTitle,
  });

  /// 目標の行動項目を、記録の型として読み替える。
  ///
  /// 日記の材料にはしない（useInDiary: false）。目標の数値は日々の事実というより
  /// 追跡の記録で、本文に「体重62.5kg」と書かれても日記としては座りが悪いため。
  /// 出来事として話したければ、聴取の中で話題に選べばよい。
  factory RecordField.fromGoalAction(Goal goal, GoalAction action) {
    return RecordField(
      id: action.answerKey,
      label: action.label,
      kind: action.isNumeric ? FieldKind.numeric : FieldKind.yesNo,
      unit: action.unit,
      target: action.target,
      useInDiary: false,
      goalId: goal.id,
      goalTitle: goal.title,
    );
  }

  factory RecordField.fromMap(Map<String, dynamic> map) {
    final rawWeekdays = (map['weekdays'] as List<dynamic>?)
        ?.whereType<int>()
        .where((d) => d >= 1 && d <= 7)
        .toSet()
        .toList()
      ?..sort();
    final target = map['target'];
    return RecordField(
      id: map['id'] as String? ?? '',
      label: map['label'] as String? ?? '',
      kind: fieldKindFrom(map['kind'] as String?),
      unit: map['unit'] as String? ?? '',
      target: target is num ? target.toDouble() : null,
      choices:
          (map['choices'] as List<dynamic>?)
              ?.whereType<String>()
              .where((c) => c.trim().isNotEmpty)
              .toList() ??
          const [],
      // 空リストは「永久に表へ出ない」状態なので、毎日に戻して救済する
      weekdays: (rawWeekdays == null || rawWeekdays.isEmpty)
          ? allWeekdays
          : rawWeekdays,
      source: fieldSourceFrom(map['source'] as String?),
      useInDiary: map['useInDiary'] as bool? ?? true,
      shareWithAi: map['shareWithAi'] as bool? ?? true,
      active: map['active'] as bool? ?? true,
    );
  }

  // goalId / goalTitle は書かない（目標の項目は settings/fields に保存しないため）。
  // 出所が分からないものはキーごと書かない。既定値で埋めると、読み直したときに
  // 出所が判明したように見えてしまう。
  Map<String, dynamic> toMap() => {
    'id': id,
    'label': label,
    'kind': fieldKindTo(kind),
    'unit': unit,
    'target': ?target,
    'choices': choices,
    'weekdays': weekdays,
    if (source != null) 'source': fieldSourceTo(source!),
    'useInDiary': useInDiary,
    'shareWithAi': shareWithAi,
    'active': active,
  };

  RecordField copyWith({
    String? label,
    FieldKind? kind,
    String? unit,
    List<String>? choices,
    List<int>? weekdays,
    bool? useInDiary,
    bool? shareWithAi,
    bool? active,
  }) {
    return RecordField(
      id: id,
      label: label ?? this.label,
      kind: kind ?? this.kind,
      unit: unit ?? this.unit,
      target: target,
      choices: choices ?? this.choices,
      weekdays: weekdays ?? this.weekdays,
      source: source,
      useInDiary: useInDiary ?? this.useInDiary,
      shareWithAi: shareWithAi ?? this.shareWithAi,
      active: active ?? this.active,
      goalId: goalId,
      goalTitle: goalTitle,
    );
  }

  bool get isGoal => goalId != null;

  /// 後から足した項目か（設定画面で足したもの・相談室で採用したもの）。
  /// 設定画面で「削除」を出してよいかの判定に使う（プリセットは消さず切り替えるだけ）。
  bool get isCustom => id.startsWith(kCustomFieldPrefix);

  /// 端末と連携して足した項目か。値は端末から入り、手でも直せる。
  /// 記入状況（「記入 3/6」）の数には入れない（daily_record.dart の recordProgress を参照）。
  bool get isHealth => id.startsWith(kHealthFieldPrefix);

  /// 日記の本文に使ってよいか。AI に渡さない項目は、日記にも使わない。
  bool get usableInDiary => shareWithAi && useInDiary;

  /// AI へ渡すときのラベル。目標の項目は目標名を添える。
  /// 別々の目標に同じ「体重」があると、項目名だけではどちらの記録か区別が付かないため。
  String get promptLabel =>
      goalTitle == null ? label : '目標「$goalTitle」の「$label」';
}

/// 最初に用意する記録項目。settings/fields がまだ無いユーザーにはこれを返す。
///
/// 全部を有効にしないのは、毎日答える項目が多いほど記録が続かなくなるため。
/// 食事と勉強は使う人だけが設定で有効にする。
const List<RecordField> kPresetFields = [
  RecordField(
    id: kSleepFieldId,
    label: '睡眠時間',
    kind: FieldKind.numeric,
    unit: '時間',
    source: FieldSource.preset,
  ),
  RecordField(
    id: kMoodFieldId,
    label: '今日の気分',
    kind: FieldKind.choice,
    choices: kMoodChoices,
    source: FieldSource.preset,
  ),
  RecordField(
    id: kMorningFieldId,
    label: '午前にしたこと',
    source: FieldSource.preset,
  ),
  RecordField(
    id: kAfternoonFieldId,
    label: '午後にしたこと',
    source: FieldSource.preset,
  ),
  RecordField(
    id: kEveningFieldId,
    label: '夜にしたこと',
    source: FieldSource.preset,
  ),
  RecordField(
    id: kExerciseFieldId,
    label: '運動した',
    kind: FieldKind.yesNo,
    source: FieldSource.preset,
  ),
  RecordField(
    id: kStudyFieldId,
    label: '勉強した',
    kind: FieldKind.yesNo,
    source: FieldSource.preset,
    active: false,
  ),
  RecordField(
    id: kFoodFieldId,
    label: '食べたもの',
    source: FieldSource.preset,
    active: false,
  ),
];
