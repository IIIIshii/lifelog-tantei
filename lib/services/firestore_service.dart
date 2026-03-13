import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_settings.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ユーザー設定

  Future<UserSettings> getUserSettings(String uid) async {
    final doc = await _db
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('preferences')
        .get();
    if (doc.exists && doc.data() != null) {
      return UserSettings.fromMap(doc.data()!);
    }
    return UserSettings.defaults();
  }

  Future<void> saveUserSettings(String uid, UserSettings settings) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('preferences')
        .set(settings.toMap());
  }

  Future<String?> getTodayDiary(String uid, String date) async {
    final doc = await _db
        .collection('users')
        .doc(uid)
        .collection('entries')
        .doc(date)
        .get();
    if (doc.exists && doc.data()?['diary'] != null) {
      return doc.data()!['diary'] as String;
    }
    return null;
  }

  Future<void> saveMessage(
      String uid, String date, String role, String text, int order) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('entries')
        .doc(date)
        .collection('conversation')
        .add({
      'role': role,
      'text': text,
      'order': order,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> saveDiary(String uid, String date, String diary) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('entries')
        .doc(date)
        .set({
      'diary': diary,
      'timestamp': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Query<Map<String, dynamic>> entriesQuery(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('entries')
        .where('diary', isNotEqualTo: null)
        .orderBy('diary')
        .orderBy('timestamp', descending: true);
  }

  Future<void> saveStats(
      String uid, String date, Map<String, dynamic> stats) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('entries')
        .doc(date)
        .set({'stats': stats}, SetOptions(merge: true));
  }

  /// 直近 [days] 日分のエントリを日付昇順で返す
  Future<List<Map<String, dynamic>>> getStatsHistory(
      String uid, {int days = 30}) async {
    final since = DateTime.now().subtract(Duration(days: days));
    final sinceStr = since.toIso8601String().split('T')[0];
    final snap = await _db
        .collection('users')
        .doc(uid)
        .collection('entries')
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: sinceStr)
        .orderBy(FieldPath.documentId)
        .get();
    return snap.docs.map((d) {
      final data = Map<String, dynamic>.from(d.data());
      data['date'] = d.id;
      return data;
    }).toList();
  }
}
