import 'package:cloud_firestore/cloud_firestore.dart';

// users/{uid} 本体のプロフィール情報を保持するモデル
// Google認証への移行を見据え、displayName / email / providerId を持つ
class AppUser {
  final String uid;
  final String? displayName;
  final String? email;
  final String? photoUrl;
  final String providerId; // "anonymous" または "google.com"
  final DateTime? createdAt;
  final DateTime? lastSignInAt;
  final int schemaVersion; // 将来のマイグレーション識別用

  const AppUser({
    required this.uid,
    this.displayName,
    this.email,
    this.photoUrl,
    required this.providerId,
    this.createdAt,
    this.lastSignInAt,
    this.schemaVersion = 1,
  });

  factory AppUser.fromMap(String uid, Map<String, dynamic> map) {
    return AppUser(
      uid: uid,
      displayName: map['displayName'] as String?,
      email: map['email'] as String?,
      photoUrl: map['photoUrl'] as String?,
      providerId: map['providerId'] as String? ?? 'anonymous',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      lastSignInAt: (map['lastSignInAt'] as Timestamp?)?.toDate(),
      schemaVersion: map['schemaVersion'] as int? ?? 1,
    );
  }

  // Firestore書き込み用マップ
  // createdAt / lastSignInAt は呼び出し側（FirestoreService）が
  // FieldValue.serverTimestamp() で別途付与する
  Map<String, dynamic> toMap() {
    return {
      'displayName': displayName,
      'email': email,
      'photoUrl': photoUrl,
      'providerId': providerId,
      'schemaVersion': schemaVersion,
    };
  }

  AppUser copyWith({
    String? displayName,
    String? email,
    String? photoUrl,
    String? providerId,
    DateTime? createdAt,
    DateTime? lastSignInAt,
    int? schemaVersion,
  }) {
    return AppUser(
      uid: uid,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      photoUrl: photoUrl ?? this.photoUrl,
      providerId: providerId ?? this.providerId,
      createdAt: createdAt ?? this.createdAt,
      lastSignInAt: lastSignInAt ?? this.lastSignInAt,
      schemaVersion: schemaVersion ?? this.schemaVersion,
    );
  }
}
