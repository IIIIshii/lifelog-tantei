// ユーザーの設定（担当探偵・通知）を保持するモデル。
// users/{uid}/settings/preferences に保存する。
//
// 記録項目の定義はここに持たない（settings/fields の RecordField を参照）。
// このドキュメントは .set() の全置換で保存されるので、相談室など他の画面からも
// 書き足される記録項目を同居させると、古い設定を握ったまま保存した側が
// 項目を巻き戻してしまうため。
class UserSettings {
  final bool notificationEnabled; // 毎日リマインダー通知を送るか
  final int notificationHour; // 通知時刻：時（0–23）
  final int notificationMinute; // 通知時刻：分（0–59）
  final String selectedRole; // 選択されたロール

  const UserSettings({
    this.notificationEnabled = false,
    this.notificationHour = 21,
    this.notificationMinute = 0,
    this.selectedRole = 'hardboiled',
  });

  // デフォルト設定を返すファクトリ
  factory UserSettings.defaults() => const UserSettings();

  // Firestoreのマップからインスタンスを生成するファクトリ
  factory UserSettings.fromMap(Map<String, dynamic> map) {
    return UserSettings(
      notificationEnabled: map['notificationEnabled'] as bool? ?? false,
      notificationHour: map['notificationHour'] as int? ?? 21,
      notificationMinute: map['notificationMinute'] as int? ?? 0,
      selectedRole: map['selectedRole'] as String? ?? 'hardboiled',
    );
  }

  // Firestoreへ保存する形にシリアライズする
  Map<String, dynamic> toMap() {
    return {
      'notificationEnabled': notificationEnabled,
      'notificationHour': notificationHour,
      'notificationMinute': notificationMinute,
      'selectedRole': selectedRole,
    };
  }

  // 一部のフィールドだけ変更した新しいインスタンスを返すメソッド
  UserSettings copyWith({
    bool? notificationEnabled,
    int? notificationHour,
    int? notificationMinute,
    String? selectedRole,
  }) {
    return UserSettings(
      notificationEnabled: notificationEnabled ?? this.notificationEnabled,
      notificationHour: notificationHour ?? this.notificationHour,
      notificationMinute: notificationMinute ?? this.notificationMinute,
      selectedRole: selectedRole ?? this.selectedRole,
    );
  }
}
