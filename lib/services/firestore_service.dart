import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

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
}
