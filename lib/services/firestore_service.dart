import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_settings.dart';

// Firestoreへのデータ読み書きを担当するサービスクラス
class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ユーザーの設定をFirestoreから取得する（存在しなければデフォルト値を返す）
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

  // ユーザーの設定をFirestoreに保存する
  Future<void> saveUserSettings(String uid, UserSettings settings) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('preferences')
        .set(settings.toMap());
  }

  // 指定日の日記テキストをFirestoreから取得する（未生成の場合はnullを返す）
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

  // 指定日の会話メッセージ数を返す（追記時のconversationOrderオフセット計算に使う）
  Future<int> getMessageCount(String uid, String date) async {
    final snap = await _db
        .collection('users')
        .doc(uid)
        .collection('entries')
        .doc(date)
        .collection('conversation')
        .count()
        .get();
    return snap.count ?? 0;
  }

  // 会話の1メッセージをFirestoreに保存する（順序orderで並び替えできるようにする）
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

  // 質問キー→回答テキストのマップをFirestoreに保存する（既存データとマージする）
  // numericAnswers が渡された場合は数値データも同時に保存する
  Future<void> saveAnswers(
      String uid, String date, Map<String, String> answers,
      {Map<String, double>? numericAnswers}) async {
    if (answers.isEmpty && (numericAnswers == null || numericAnswers.isEmpty)) {
      return;
    }
    final data = <String, dynamic>{};
    if (answers.isNotEmpty) data['answers'] = answers;
    if (numericAnswers != null && numericAnswers.isNotEmpty) {
      data['numericAnswers'] = numericAnswers;
    }
    await _db
        .collection('users')
        .doc(uid)
        .collection('entries')
        .doc(date)
        .set(data, SetOptions(merge: true));
  }

  // 直近 days 日分のエントリを日付文字列とデータのペアで返す
  Future<List<MapEntry<String, Map<String, dynamic>>>> getRecentEntries(
      String uid, int days) async {
    final now = DateTime.now();
    final from = now.subtract(Duration(days: days - 1));
    final fromStr = from.toIso8601String().split('T')[0];
    final toStr = now.toIso8601String().split('T')[0];

    final snap = await _db
        .collection('users')
        .doc(uid)
        .collection('entries')
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: fromStr)
        .where(FieldPath.documentId, isLessThanOrEqualTo: toStr)
        .get();

    return snap.docs.map((doc) => MapEntry(doc.id, doc.data())).toList();
  }

  // 生成した日記テキストをFirestoreに保存する（既存データとマージする）
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

  // 全エントリを日付の降順で返す（CSVエクスポート用）
  Future<List<MapEntry<String, Map<String, dynamic>>>> getAllEntries(
      String uid) async {
    final snap = await _db
        .collection('users')
        .doc(uid)
        .collection('entries')
        .get();
    final entries =
        snap.docs.map((doc) => MapEntry(doc.id, doc.data())).toList();
    entries.sort((a, b) => b.key.compareTo(a.key));
    return entries;
  }

  // 日記エントリ一覧を取得するクエリを返す
  // ソートはクライアント側でドキュメントID（YYYY-MM-DD）の降順で行う
  Query<Map<String, dynamic>> entriesQuery(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('entries');
  }
}
