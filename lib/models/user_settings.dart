import 'package:cloud_firestore/cloud_firestore.dart';

// ユーザーの記録設定を保持するモデル
// customQuestions は独立サブコレクション users/{uid}/customQuestions/{id} に移行したため
// このモデルからは除外している
class UserSettings {
  final bool recordEvent; // 今日の印象的な出来事を記録するか（デフォルトON）
  final bool recallAssist; // 午前・午後・夜の時間帯別質問を追加するか
  final bool recordSleep; // 睡眠時間を記録するか
  final bool recordFood; // 食事内容を記録するか
  final bool recordExercise; // 運動習慣を記録するか
  final bool recordStudy; // 勉強内容を記録するか
  final bool notificationEnabled; // 毎日リマインダー通知を送るか
  final int notificationHour; // 通知時刻：時（0–23）
  final int notificationMinute; // 通知時刻：分（0–59）
  final DateTime? updatedAt; // 最終更新時刻（FirestoreService が serverTimestamp で更新）

  const UserSettings({
    this.recordEvent = true,
    this.recallAssist = false,
    this.recordSleep = false,
    this.recordFood = false,
    this.recordExercise = false,
    this.recordStudy = false,
    this.notificationEnabled = false,
    this.notificationHour = 21,
    this.notificationMinute = 0,
    this.updatedAt,
  });

  // デフォルト設定を返すファクトリ
  factory UserSettings.defaults() => const UserSettings();

  // Firestoreのマップからインスタンスを生成するファクトリ
  factory UserSettings.fromMap(Map<String, dynamic> map) {
    return UserSettings(
      recordEvent: map['recordEvent'] as bool? ?? true,
      recallAssist: map['recallAssist'] as bool? ?? false,
      recordSleep: map['recordSleep'] as bool? ?? false,
      recordFood: map['recordFood'] as bool? ?? false,
      recordExercise: map['recordExercise'] as bool? ?? false,
      recordStudy: map['recordStudy'] as bool? ?? false,
      notificationEnabled: map['notificationEnabled'] as bool? ?? false,
      notificationHour: map['notificationHour'] as int? ?? 21,
      notificationMinute: map['notificationMinute'] as int? ?? 0,
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  // Firestore書き込み用マップ
  // updatedAt は FirestoreService が FieldValue.serverTimestamp() で別途付与する
  Map<String, dynamic> toMap() {
    return {
      'recordEvent': recordEvent,
      'recallAssist': recallAssist,
      'recordSleep': recordSleep,
      'recordFood': recordFood,
      'recordExercise': recordExercise,
      'recordStudy': recordStudy,
      'notificationEnabled': notificationEnabled,
      'notificationHour': notificationHour,
      'notificationMinute': notificationMinute,
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
    bool? notificationEnabled,
    int? notificationHour,
    int? notificationMinute,
    DateTime? updatedAt,
  }) {
    return UserSettings(
      recordEvent: recordEvent ?? this.recordEvent,
      recallAssist: recallAssist ?? this.recallAssist,
      recordSleep: recordSleep ?? this.recordSleep,
      recordFood: recordFood ?? this.recordFood,
      recordExercise: recordExercise ?? this.recordExercise,
      recordStudy: recordStudy ?? this.recordStudy,
      notificationEnabled: notificationEnabled ?? this.notificationEnabled,
      notificationHour: notificationHour ?? this.notificationHour,
      notificationMinute: notificationMinute ?? this.notificationMinute,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
