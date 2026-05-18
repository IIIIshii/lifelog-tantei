import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/app_user.dart';
import '../models/custom_question.dart';
import '../models/day_entry.dart';
import '../models/response_entry.dart';
import '../models/user_settings.dart';

// Firestoreへのデータ読み書きを担当するサービスクラス
// スキーマ：
//   users/{uid}
//     ├── settings/preferences        (1 doc)
//     ├── customQuestions/{questionId} (subcollection)
//     └── days/{YYYY-MM-DD}
//           └── conversation/{autoId}  (subcollection)
class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ──────────────────────────────────────────
  // パスヘルパー
  // ──────────────────────────────────────────

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _db.collection('users').doc(uid);

  DocumentReference<Map<String, dynamic>> _preferencesDoc(String uid) =>
      _userDoc(uid).collection('settings').doc('preferences');

  CollectionReference<Map<String, dynamic>> _customQuestionsColl(String uid) =>
      _userDoc(uid).collection('customQuestions');

  // ResponseEntry.questionRef に保存するため公開
  DocumentReference<Map<String, dynamic>> customQuestionRef(
          String uid, String questionId) =>
      _customQuestionsColl(uid).doc(questionId);

  CollectionReference<Map<String, dynamic>> _daysColl(String uid) =>
      _userDoc(uid).collection('days');

  DocumentReference<Map<String, dynamic>> _dayDoc(String uid, String date) =>
      _daysColl(uid).doc(date);

  CollectionReference<Map<String, dynamic>> _conversationColl(
          String uid, String date) =>
      _dayDoc(uid, date).collection('conversation');

  // ──────────────────────────────────────────
  // AppUser (users/{uid})
  // ──────────────────────────────────────────

  // ユーザープロフィールを取得（未作成ならnull）
  Future<AppUser?> getAppUser(String uid) async {
    final doc = await _userDoc(uid).get();
    if (!doc.exists || doc.data() == null) return null;
    return AppUser.fromMap(uid, doc.data()!);
  }

  // ユーザードキュメントを冪等に作成/更新する
  // - 新規時: createdAt + lastSignInAt + 全フィールドをセット
  // - 既存時: lastSignInAt と現在の providerId / プロフィール情報を更新
  // 呼び出し側: AuthService の sign-in 完了直後（匿名/Google問わず）
  Future<void> ensureAppUser({
    required String uid,
    required String providerId,
    String? displayName,
    String? email,
    String? photoUrl,
  }) async {
    final docRef = _userDoc(uid);
    final snap = await docRef.get();
    final data = <String, dynamic>{
      'providerId': providerId,
      'displayName': displayName,
      'email': email,
      'photoUrl': photoUrl,
      'schemaVersion': 1,
      'lastSignInAt': FieldValue.serverTimestamp(),
    };
    if (!snap.exists) {
      data['createdAt'] = FieldValue.serverTimestamp();
    }
    await docRef.set(data, SetOptions(merge: true));
  }

  // ──────────────────────────────────────────
  // UserSettings (users/{uid}/settings/preferences)
  // ──────────────────────────────────────────

  // ユーザーの設定をFirestoreから取得（存在しなければデフォルト値を返す）
  Future<UserSettings> getUserSettings(String uid) async {
    final doc = await _preferencesDoc(uid).get();
    if (doc.exists && doc.data() != null) {
      return UserSettings.fromMap(doc.data()!);
    }
    return UserSettings.defaults();
  }

  // ユーザーの設定をFirestoreに保存（updatedAtを自動付与）
  Future<void> saveUserSettings(String uid, UserSettings settings) async {
    final data = settings.toMap();
    data['updatedAt'] = FieldValue.serverTimestamp();
    await _preferencesDoc(uid).set(data, SetOptions(merge: true));
  }

  // ──────────────────────────────────────────
  // CustomQuestions (users/{uid}/customQuestions/{id})
  // ──────────────────────────────────────────

  // アクティブな質問（archivedAt==null）を order 昇順で取得
  Future<List<CustomQuestion>> getActiveCustomQuestions(String uid) async {
    final snap = await _customQuestionsColl(uid)
        .where('archivedAt', isNull: true)
        .orderBy('order')
        .get();
    return snap.docs
        .map((d) => CustomQuestion.fromMap(d.id, d.data()))
        .toList();
  }

  // archive 済みも含めて全て取得
  // 過去日記の表示で archived な質問の文脈を引きたい場合に使う
  Future<List<CustomQuestion>> getAllCustomQuestions(String uid) async {
    final snap = await _customQuestionsColl(uid).orderBy('order').get();
    return snap.docs
        .map((d) => CustomQuestion.fromMap(d.id, d.data()))
        .toList();
  }

  // アクティブな質問の変更を監視するストリーム
  Stream<List<CustomQuestion>> watchActiveCustomQuestions(String uid) {
    return _customQuestionsColl(uid)
        .where('archivedAt', isNull: true)
        .orderBy('order')
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => CustomQuestion.fromMap(d.id, d.data()))
            .toList());
  }

  // 新規追加（auto-IDを発番し、生成された質問IDを返す）
  Future<String> addCustomQuestion(
    String uid, {
    required String text,
    QuestionType type = QuestionType.text,
    List<String>? choices,
    String? unit,
    double order = 0,
  }) async {
    final docRef = _customQuestionsColl(uid).doc();
    await docRef.set({
      'text': text,
      'type': type.value,
      'choices': choices,
      'unit': unit,
      'enabled': true,
      'order': order,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'archivedAt': null,
    });
    return docRef.id;
  }

  // 既存質問を更新（text / type / order / enabled 等）
  // archivedAt は対象外。archive は archiveCustomQuestion を使う
  Future<void> updateCustomQuestion(
      String uid, CustomQuestion question) async {
    final data = question.toMap();
    data['updatedAt'] = FieldValue.serverTimestamp();
    await _customQuestionsColl(uid)
        .doc(question.id)
        .set(data, SetOptions(merge: true));
  }

  // 論理削除（archivedAt をセット）
  // 過去日記からの questionRef 参照が壊れないように完全削除はしない
  Future<void> archiveCustomQuestion(String uid, String questionId) async {
    await _customQuestionsColl(uid).doc(questionId).set(
      {
        'archivedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  // ──────────────────────────────────────────
  // Days (users/{uid}/days/{date})
  // ──────────────────────────────────────────

  // 指定日のデータを取得（未生成の場合はnull）
  Future<DayEntry?> getDay(String uid, String date) async {
    final doc = await _dayDoc(uid, date).get();
    if (!doc.exists || doc.data() == null) return null;
    return DayEntry.fromMap(date, doc.data()!);
  }

  // 指定日の日記テキストのみ取得
  Future<String?> getDayDiary(String uid, String date) async {
    final day = await getDay(uid, date);
    return day?.diary;
  }

  // 1日丸ごと保存
  // - metrics は responses から数値質問だけ抽出して自動生成
  //   （呼び出し側が忘れる余地をなくし、データ整合性を保証）
  // - 新規時のみ createdAt をセット、updatedAt は毎回更新
  Future<void> saveDay(String uid, DayEntry day) async {
    final docRef = _dayDoc(uid, day.date);
    final snap = await docRef.get();

    final metrics = <String, double>{};
    for (final r in day.responses) {
      if (r.answerNumber != null) {
        metrics[r.questionKey] = r.answerNumber!;
      }
    }

    final data = <String, dynamic>{
      'diary': day.diary,
      'diarySource': day.diarySource?.value,
      'responses': day.responses.map((r) => r.toMap()).toList(),
      'metrics': metrics,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (!snap.exists) {
      data['createdAt'] = FieldValue.serverTimestamp();
    }
    await docRef.set(data, SetOptions(merge: true));
  }

  // 日記テキストのみ保存（編集画面用、source指定可）
  Future<void> saveDiaryText(
    String uid,
    String date,
    String diary,
    DiarySource source,
  ) async {
    final docRef = _dayDoc(uid, date);
    final snap = await docRef.get();
    final data = <String, dynamic>{
      'diary': diary,
      'diarySource': source.value,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (!snap.exists) {
      data['createdAt'] = FieldValue.serverTimestamp();
    }
    await docRef.set(data, SetOptions(merge: true));
  }

  // 直近 days 日分のエントリを返す
  Future<List<DayEntry>> getRecentDays(String uid, int days) async {
    final now = DateTime.now();
    final from = now.subtract(Duration(days: days - 1));
    final fromStr = from.toIso8601String().split('T')[0];
    final toStr = now.toIso8601String().split('T')[0];
    final snap = await _daysColl(uid)
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: fromStr)
        .where(FieldPath.documentId, isLessThanOrEqualTo: toStr)
        .get();
    return snap.docs.map((d) => DayEntry.fromMap(d.id, d.data())).toList();
  }

  // 全エントリを日付の降順で返す（CSVエクスポート用）
  Future<List<DayEntry>> getAllDays(String uid) async {
    final snap = await _daysColl(uid).get();
    final entries =
        snap.docs.map((d) => DayEntry.fromMap(d.id, d.data())).toList();
    entries.sort((a, b) => b.date.compareTo(a.date));
    return entries;
  }

  // 日記一覧用のクエリ（StreamBuilder で使う）
  Query<Map<String, dynamic>> daysQuery(String uid) => _daysColl(uid);

  // ──────────────────────────────────────────
  // Conversation (users/{uid}/days/{date}/conversation)
  // ──────────────────────────────────────────

  // 指定日の会話メッセージ数を返す（追記時のconversationOrderオフセット計算に使う）
  Future<int> getMessageCount(String uid, String date) async {
    final snap = await _conversationColl(uid, date).count().get();
    return snap.count ?? 0;
  }

  // 会話の1メッセージを保存（順序orderで並び替えできるようにする）
  Future<void> saveMessage(
      String uid, String date, String role, String text, int order) async {
    await _conversationColl(uid, date).add({
      'role': role,
      'text': text,
      'order': order,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // ──────────────────────────────────────────
  // Mock Data
  // ──────────────────────────────────────────

  // デモ用のモックデータを7日分書き込む
  // 冪等性のため、既存のcustomQuestionsを一度全削除してから再投入する
  // （days は同じ日付なので saveDay の merge で上書きされる）
  Future<void> seedMockData(String uid) async {
    // 1. プロフィール作成（既存ならlastSignInAt更新）
    await ensureAppUser(uid: uid, providerId: 'anonymous');

    // 2. 設定を全項目ONで上書き
    await saveUserSettings(
      uid,
      const UserSettings(
        recordEvent: true,
        recallAssist: true,
        recordSleep: true,
        recordFood: true,
        recordExercise: true,
        recordStudy: true,
      ),
    );

    // 3. 既存のcustomQuestionsを全削除（再投入時の重複防止）
    final existing = await _customQuestionsColl(uid).get();
    if (existing.docs.isNotEmpty) {
      final batch = _db.batch();
      for (final doc in existing.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }

    // 4. カスタム質問を2つ作成（モックデータの custom_0 / custom_1 に対応）
    final q0Id = await addCustomQuestion(
      uid,
      text: '今日、新しいことに挑戦したか?',
      type: QuestionType.singleChoice,
      choices: const ['はい', 'いいえ'],
      order: 1.0,
    );
    final q1Id = await addCustomQuestion(
      uid,
      text: '今日の新しい発見は?',
      type: QuestionType.text,
      order: 2.0,
    );
    final q0Ref = customQuestionRef(uid, q0Id);
    final q1Ref = customQuestionRef(uid, q1Id);

    // 5. 7日分のday entriesを書き込み
    for (final entry in _mockDayData.entries) {
      final numericRaw = entry.value['numericAnswers'] as Map;
      final numericAnswers = <String, double>{};
      numericRaw.forEach((k, v) {
        if (k is String && v is num) numericAnswers[k] = v.toDouble();
      });

      final day = _convertMockToDayEntry(
        date: entry.key,
        diary: entry.value['diary'] as String,
        answers: (entry.value['answers'] as Map).cast<String, String>(),
        numericAnswers: numericAnswers,
        q0Id: q0Id,
        q0Ref: q0Ref,
        q1Id: q1Id,
        q1Ref: q1Ref,
      );
      await saveDay(uid, day);
    }
  }

  // 質問キー → 質問文 のマップ（モック変換用、diary_page.dart の文言と一致させる）
  static const Map<String, String> _appQuestionTexts = {
    'sleep': '昨夜は何時間眠った?',
    'food': '今日、何を口にした?',
    'exercise': '身体を動かしたか?',
    'study': '今日、頭を使う作業はしたか?',
    'morning': '午前中の動向を報告してくれ。',
    'afternoon': '午後はどう動いた?',
    'evening': '夜の動向は?',
    'event_when': 'それはいつの話だ?',
    'event_where': 'どこで起きた?',
    'event_who': '誰に関わる話だ?',
    'event_what': '何があった?話してくれ。',
    'event_how': 'そのとき、どう感じた?',
  };

  // 旧スキーマ風のmockデータ（answers/numericAnswers）を新スキーマの DayEntry に変換する
  DayEntry _convertMockToDayEntry({
    required String date,
    required String diary,
    required Map<String, String> answers,
    required Map<String, double> numericAnswers,
    required String q0Id,
    required DocumentReference<Map<String, dynamic>> q0Ref,
    required String q1Id,
    required DocumentReference<Map<String, dynamic>> q1Ref,
  }) {
    final responses = <ResponseEntry>[];
    var order = 0;

    // fixed (sleep / food / exercise / study)
    for (final key in const ['sleep', 'food', 'exercise', 'study']) {
      if (answers.containsKey(key)) {
        final type = (key == 'food')
            ? QuestionType.text
            : (key == 'sleep'
                ? QuestionType.singleChoice
                : QuestionType.singleChoice);
        responses.add(ResponseEntry(
          source: ResponseSource.appFixed,
          questionKey: key,
          questionText: _appQuestionTexts[key] ?? key,
          questionType: type,
          answerText: answers[key],
          answerNumber: numericAnswers[key],
          order: order++,
        ));
      }
    }

    // userCustom (custom_0 / custom_1)
    if (answers.containsKey('custom_0')) {
      responses.add(ResponseEntry(
        source: ResponseSource.userCustom,
        questionKey: 'custom_$q0Id',
        questionRef: q0Ref,
        questionText: '今日、新しいことに挑戦したか?',
        questionType: QuestionType.singleChoice,
        answerText: answers['custom_0'],
        order: order++,
      ));
    }
    if (answers.containsKey('custom_1')) {
      responses.add(ResponseEntry(
        source: ResponseSource.userCustom,
        questionKey: 'custom_$q1Id',
        questionRef: q1Ref,
        questionText: '今日の新しい発見は?',
        questionType: QuestionType.text,
        answerText: answers['custom_1'],
        order: order++,
      ));
    }

    // recall (morning / afternoon / evening)
    for (final key in const ['morning', 'afternoon', 'evening']) {
      if (answers.containsKey(key)) {
        responses.add(ResponseEntry(
          source: ResponseSource.appRecall,
          questionKey: key,
          questionText: _appQuestionTexts[key] ?? key,
          questionType: QuestionType.text,
          answerText: answers[key],
          order: order++,
        ));
      }
    }

    // event (event_when / where / who / what / how)
    for (final key in const [
      'event_when',
      'event_where',
      'event_who',
      'event_what',
      'event_how',
    ]) {
      if (answers.containsKey(key)) {
        final isFreeText = key == 'event_what';
        responses.add(ResponseEntry(
          source: ResponseSource.appEvent,
          questionKey: key,
          questionText: _appQuestionTexts[key] ?? key,
          questionType:
              isFreeText ? QuestionType.text : QuestionType.singleChoice,
          answerText: answers[key],
          order: order++,
        ));
      }
    }

    return DayEntry(
      date: date,
      diary: diary,
      diarySource: DiarySource.ai,
      responses: responses,
    );
  }

  // mockデータ（7日分）。answers/numericAnswers は旧スキーマと同じ内容
  static const Map<String, Map<String, dynamic>> _mockDayData = {
    '2026-03-08': {
      'diary':
          '依頼人から、特定の出来事に関する証言を得た。それはプライベートな時間、カフェで初めて注文を全部英語で行った一件。依頼人はその出来事に対し「面白かった」と述べ、「店員さんが普通に対応してくれて少し拍子抜けだった」と評価した。当日の睡眠時間は7時間と記録されている。食事はトースト・カフェのパスタ・冷凍チャーハンを摂取し、運動は実施済み。学習も実施済みであった。午前中は洗濯と部屋の掃除、午後は近所のカフェで読書、夜は友人とオンラインゲームに時間を費やしていたことが確認された。',
      'answers': {
        'sleep': '7時間',
        'food': 'カフェのパスタ',
        'exercise': 'した',
        'study': 'した',
        'custom_0': 'いいえ',
        'custom_1': 'カフェで初めてオーダーを全部英語でしてみた',
        'morning': '洗濯と部屋の掃除をした',
        'afternoon': '近所のカフェで本を読んだ',
        'evening': '友人とオンラインゲームをした',
        'event_when': 'プライベート',
        'event_where': 'カフェ',
        'event_who': '自分',
        'event_what': '初めて注文を全部英語でしてみた',
        'event_how': '面白かった',
      },
      'numericAnswers': {'sleep': 7.0},
    },
    '2026-03-09': {
      'diary':
          '依頼人から、特定の出来事に関する証言を得た。それは昼、学校で図書館の自習室を初めて予約しレポートを書き上げた一件。依頼人はその出来事に対し「嬉しかった」と述べ、「静かで集中できてよかった」と評価した。当日の睡眠時間は6時間と記録されている。食事はおにぎり・学食のカレー・鍋を摂取し、運動は未実施。学習は実施済みであった。午前中は授業（統計学・線形代数）、午後は図書館での課題レポート作業、夜は夕食後すぐ就寝に時間を費やしていたことが確認された。',
      'answers': {
        'sleep': '6時間',
        'food': '学食のカレー',
        'exercise': 'していない',
        'study': 'した',
        'custom_0': 'はい',
        'custom_1': '図書館の自習室を初めて予約して使った',
        'morning': '授業（統計学・線形代数）',
        'afternoon': '図書館で課題レポートを書いた',
        'evening': '夕食後すぐ寝てしまった',
        'event_when': '昼',
        'event_where': '学校',
        'event_who': '自分',
        'event_what': '図書館の自習室を初めて予約してレポートを書き上げた',
        'event_how': '嬉しかった',
      },
      'numericAnswers': {'sleep': 6.0},
    },
    '2026-03-10': {
      'diary':
          '依頼人から、特定の出来事に関する証言を得た。それは昼、学校でPythonのgroupbyのバグをドキュメントをもとに解決した一件。依頼人はその出来事に対し「嬉しかった」と述べ、「やっと解決できてすっきりした」と評価した。当日の睡眠時間は7時間と記録されている。食事はヨーグルト・サンドイッチ・鶏むね肉の照り焼きを摂取し、運動は実施済み。学習も実施済みであった。午前中はプログラミング演習の授業、午後は研究室でのデバッグ作業、夜はジムでのランニングとストレッチに時間を費やしていたことが確認された。',
      'answers': {
        'sleep': '7時間',
        'food': '鶏むね肉の照り焼き（自炊）',
        'exercise': 'した',
        'study': 'した',
        'custom_0': 'いいえ',
        'custom_1': 'pandasのgroupbyを初めて使いこなせた',
        'morning': '授業（プログラミング演習）',
        'afternoon': '研究室でPythonのデバッグ作業',
        'evening': 'ジムでランニングとストレッチ',
        'event_when': '昼',
        'event_where': '学校',
        'event_who': '自分',
        'event_what': 'Pythonのgroupbyのバグをドキュメントをもとにやっと解決できた',
        'event_how': '嬉しかった',
      },
      'numericAnswers': {'sleep': 7.0},
    },
    '2026-03-11': {
      'diary':
          '依頼人から、特定の出来事に関する証言を得た。それは夜、居酒屋で友人とともに苦手なレバーを初めて完食した一件。依頼人はその出来事に対し「面白かった」と述べ、「不思議と食べられて自分でも驚いた」と評価した。当日の睡眠時間は5時間と記録されている。食事はファミレスのモーニング・居酒屋の唐揚げ・枝豆などを摂取し、運動は実施済み。学習も実施済みであった。午前中はオンライン講義（機械学習入門）の視聴、午後は近所の散歩と昼寝、夜は友人との居酒屋に時間を費やしていたことが確認された。',
      'answers': {
        'sleep': '5時間',
        'food': '居酒屋',
        'exercise': 'した',
        'study': 'した',
        'custom_0': 'いいえ',
        'custom_1': '居酒屋で苦手なレバーを初めて完食できた',
        'morning': 'オンライン講義（機械学習入門）の視聴',
        'afternoon': '近所を30分散歩してから昼寝',
        'evening': '友人と居酒屋に行った',
        'event_when': '夜',
        'event_where': '居酒屋',
        'event_who': '友人と',
        'event_what': '苦手なレバーを初めて完食できた',
        'event_how': '面白かった',
      },
      'numericAnswers': {'sleep': 5.0},
    },
    '2026-03-12': {
      'diary':
          '依頼人から、特定の出来事に関する証言を得た。それは昼、学校でヒープを手書きで1から実装した一件。依頼人はその出来事に対し「嬉しかった」と述べ、「意外とすらすら書けて自信がついた」と評価した。当日の睡眠時間は8時間と記録されている。食事は食パン・学食の日替わり定食・コンビニのパスタを摂取し、運動は未実施。学習は実施済みであった。午前中は英語・データ構造の授業、午後は図書館での試験勉強、夜は入浴と読書に時間を費やしていたことが確認された。',
      'answers': {
        'sleep': '8時間',
        'food': '日替わり定食',
        'exercise': 'していない',
        'study': 'した',
        'custom_0': 'はい',
        'custom_1': 'ヒープの実装を手書きで1から書いてみた',
        'morning': '授業（英語・データ構造）',
        'afternoon': '図書館で試験勉強',
        'evening': '帰宅後すぐ入浴・読書',
        'event_when': '昼',
        'event_where': '学校',
        'event_who': '自分',
        'event_what': 'ヒープを手書きで実装してみたらすらすら書けた',
        'event_how': '嬉しかった',
      },
      'numericAnswers': {'sleep': 8.0},
    },
    '2026-03-13': {
      'diary':
          '依頼人から、特定の出来事に関する証言を得た。それは夜、職場でバイト中に常連客へ自分から話しかけた一件。依頼人はその出来事に対し「嬉しかった」と述べ、「新メニューの感想を聞けてよかった」と評価した。当日の睡眠時間は6時間と記録されている。食事はカップ麺・学食のラーメン・まかないのカレーを摂取し、運動は未実施。学習は実施済みであった。午前中は確率論の授業と小テスト、午後はカフェでのアルバイト、夜は帰宅後シャワーを浴びて就寝に時間を費やしていたことが確認された。',
      'answers': {
        'sleep': '6時間',
        'food': 'アルバイト先でまかない（カレー）',
        'exercise': 'していない',
        'study': 'した',
        'custom_0': 'いいえ',
        'custom_1': 'バイト中に常連さんから新メニューの感想を自分から聞いてみた',
        'morning': '授業（確率論）・小テスト',
        'afternoon': 'カフェでアルバイト（16〜21時）',
        'evening': '帰宅後シャワーを浴びて就寝',
        'event_when': '夜',
        'event_where': '職場',
        'event_who': '自分',
        'event_what': 'バイト中に常連さんに自分から話しかけて新メニューの感想を聞いた',
        'event_how': '嬉しかった',
      },
      'numericAnswers': {'sleep': 6.0},
    },
    '2026-03-14': {
      'diary':
          '依頼人から、特定の出来事に関する証言を得た。それはプライベートな時間、自宅でFlutterとGemini APIを連携させAIアプリを初めて動かした一件。依頼人はその出来事に対し「嬉しかった」と述べ、「初めてAIが返答した瞬間は感動だった」と評価した。当日の睡眠時間は9時間と記録されている。食事はホットケーキ・デリバリーのピザ・カップ麺を摂取し、運動は未実施。学習は実施済みであった。午前中はゆっくり起床しYoutubeを見ながらストレッチ、午後はハッカソンの作業、夜はレビュー準備に時間を費やしていたことが確認された。',
      'answers': {
        'sleep': '9時間',
        'food': 'デリバリーのピザ',
        'exercise': 'していない',
        'study': 'した',
        'custom_0': 'いいえ',
        'custom_1': 'Gemini APIを使ったアプリを初めて動かせた',
        'morning': 'ゆっくり起床・Youtubeを見ながらストレッチ',
        'afternoon': 'ハッカソンの作業（Flutterアプリ開発）',
        'evening': '作業の続き・レビュー準備',
        'event_when': 'プライベート',
        'event_where': '自宅',
        'event_who': '自分',
        'event_what': 'FlutterとGemini APIを連携させてAIアプリが初めて動いた',
        'event_how': '嬉しかった',
      },
      'numericAnswers': {'sleep': 9.0},
    },
  };
}
