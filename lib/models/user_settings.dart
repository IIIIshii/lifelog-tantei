class UserSettings {
  final bool recordEvent;
  final bool recallAssist;
  final bool recordSleep;
  final bool recordFood;
  final bool recordExercise;
  final bool recordStudy;
  final List<String> customQuestions;
  final bool notificationEnabled;
  final int notificationHour;
  final int notificationMinute;

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
  });

  factory UserSettings.defaults() => const UserSettings();

  factory UserSettings.fromMap(Map<String, dynamic> map) {
    return UserSettings(
      recordEvent: map['recordEvent'] as bool? ?? true,
      recallAssist: map['recallAssist'] as bool? ?? false,
      recordSleep: map['recordSleep'] as bool? ?? false,
      recordFood: map['recordFood'] as bool? ?? false,
      recordExercise: map['recordExercise'] as bool? ?? false,
      recordStudy: map['recordStudy'] as bool? ?? false,
      customQuestions:
          (map['customQuestions'] as List<dynamic>?)?.cast<String>() ?? [],
      notificationEnabled: map['notificationEnabled'] as bool? ?? false,
      notificationHour: map['notificationHour'] as int? ?? 21,
      notificationMinute: map['notificationMinute'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'recordEvent': recordEvent,
      'recallAssist': recallAssist,
      'recordSleep': recordSleep,
      'recordFood': recordFood,
      'recordExercise': recordExercise,
      'recordStudy': recordStudy,
      'customQuestions': customQuestions,
      'notificationEnabled': notificationEnabled,
      'notificationHour': notificationHour,
      'notificationMinute': notificationMinute,
    };
  }

  UserSettings copyWith({
    bool? recordEvent,
    bool? recallAssist,
    bool? recordSleep,
    bool? recordFood,
    bool? recordExercise,
    bool? recordStudy,
    List<String>? customQuestions,
    bool? notificationEnabled,
    int? notificationHour,
    int? notificationMinute,
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
    );
  }
}
