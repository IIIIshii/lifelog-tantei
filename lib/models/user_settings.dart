import 'package:uuid/uuid.dart';

// カスタム質問1件を表すモデル
// id は追加時に発行される不変の識別子で、回答の紐付けキーとして使用する
// （並べ替え・削除・将来の質問文編集を行っても id は変わらない）
class CustomQuestion {
  final String id;
  final String text;

  const CustomQuestion({required this.id, required this.text});

  factory CustomQuestion.fromMap(Map<String, dynamic> map) {
    return CustomQuestion(
      id: map['id'] as String,
      text: map['text'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {'id': id, 'text': text};
}

// ユーザーの記録設定を保持するモデル
class UserSettings {
  final bool recordEvent; // 今日の印象的な出来事を記録するか（デフォルトON）
  final bool recallAssist; // 午前・午後・夜の時間帯別質問を追加するか
  final bool recordSleep; // 睡眠時間を記録するか
  final bool recordFood; // 食事内容を記録するか
  final bool recordExercise; // 運動習慣を記録するか
  final bool recordStudy; // 勉強内容を記録するか
  final List<CustomQuestion> customQuestions; // ユーザーが自由に追加したカスタム質問リスト
  final bool notificationEnabled; // 毎日リマインダー通知を送るか
  final int notificationHour; // 通知時刻：時（0–23）
  final int notificationMinute; // 通知時刻：分（0–59）
  final String selectedRole; // 選択されたロール

  const UserSettings({
    this.recordEvent = true,
    this.recallAssist = false,
    this.recordSleep = false,
    this.recordFood = false,
    this.recordExercise = false,
    this.recordStudy = false,
    this.customQuestions = const [],
    this.notificationEnabled = false,
    this.notificationHour = 21,
    this.notificationMinute = 0,
    this.selectedRole = 'hardboiled',
  });

  // デフォルト設定を返すファクトリ
  factory UserSettings.defaults() => const UserSettings();

  // Firestoreのマップからインスタンスを生成するファクトリ
  // customQuestions の各要素は旧形式（String）・新形式（Map）どちらも受け付ける。
  // 旧形式の場合はここでidを新規発行する（呼び出し元のFirestoreServiceが
  // 書き戻しを行うことで、以降の読み込みは新形式として扱われる）
  factory UserSettings.fromMap(Map<String, dynamic> map) {
    return UserSettings(
      recordEvent: map['recordEvent'] as bool? ?? true,
      recallAssist: map['recallAssist'] as bool? ?? false,
      recordSleep: map['recordSleep'] as bool? ?? false,
      recordFood: map['recordFood'] as bool? ?? false,
      recordExercise: map['recordExercise'] as bool? ?? false,
      recordStudy: map['recordStudy'] as bool? ?? false,
      customQuestions: (map['customQuestions'] as List<dynamic>?)
              ?.map((e) => e is String
                  ? CustomQuestion(id: const Uuid().v4(), text: e)
                  : CustomQuestion.fromMap(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          [],
      notificationEnabled: map['notificationEnabled'] as bool? ?? false,
      notificationHour: map['notificationHour'] as int? ?? 21,
      notificationMinute: map['notificationMinute'] as int? ?? 0,
      selectedRole: map['selectedRole'] as String? ?? 'hardboiled',
    );
  }

  // customQuestions に旧形式（String）が含まれているかを判定する
  // FirestoreServiceがこれを見て、移行後のデータを書き戻すかどうかを決める
  static bool needsCustomQuestionsMigration(Map<String, dynamic> map) {
    final raw = map['customQuestions'] as List<dynamic>?;
    return raw != null && raw.any((e) => e is String);
  }

  // FirestoreへのマップにシリアライズするメソッドFirestoreへ保存する際に使用
  Map<String, dynamic> toMap() {
    return {
      'recordEvent': recordEvent,
      'recallAssist': recallAssist,
      'recordSleep': recordSleep,
      'recordFood': recordFood,
      'recordExercise': recordExercise,
      'recordStudy': recordStudy,
      'customQuestions': customQuestions.map((q) => q.toMap()).toList(),
      'notificationEnabled': notificationEnabled,
      'notificationHour': notificationHour,
      'notificationMinute': notificationMinute,
      'selectedRole': selectedRole,
    };
  }

  // 一部のフィールドだけ変更した新しいインスタンスを返すメソッド
  UserSettings copyWith({
    bool? recordEvent,
    bool? recallAssist,
    bool? recordSleep,
    bool? recordFood,
    bool? recordExercise,
    bool? recordStudy,
    List<CustomQuestion>? customQuestions,
    bool? notificationEnabled,
    int? notificationHour,
    int? notificationMinute,
    String? selectedRole,
  }) {
    return UserSettings(
      recordEvent: recordEvent ?? this.recordEvent,
      recallAssist: recallAssist ?? this.recallAssist,
      recordSleep: recordSleep ?? this.recordSleep,
      recordFood: recordFood ?? this.recordFood,
      recordExercise: recordExercise ?? this.recordExercise,
      recordStudy: recordStudy ?? this.recordStudy,
      customQuestions: customQuestions ?? this.customQuestions,
      notificationEnabled: notificationEnabled ?? this.notificationEnabled,
      notificationHour: notificationHour ?? this.notificationHour,
      notificationMinute: notificationMinute ?? this.notificationMinute,
      selectedRole: selectedRole ?? this.selectedRole,
    );
  }
}
