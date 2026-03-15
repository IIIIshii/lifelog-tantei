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

  // デモ用のモックデータを7日分Firestoreに書き込む
  Future<void> seedMockData(String uid) async {
    final entries = {
      '2026-03-08': {
        'diary': '依頼人から、特定の出来事に関する証言を得た。それはプライベートな時間、カフェで初めて注文を全部英語で行った一件。依頼人はその出来事に対し「面白かった」と述べ、「店員さんが普通に対応してくれて少し拍子抜けだった」と評価した。当日の睡眠時間は7時間と記録されている。食事はトースト・カフェのパスタ・冷凍チャーハンを摂取し、運動は実施済み。学習も実施済みであった。午前中は洗濯と部屋の掃除、午後は近所のカフェで読書、夜は友人とオンラインゲームに時間を費やしていたことが確認された。',
        'answers': {
          'sleep': '7時間',
          'food': '朝：トースト、卵焼き / 昼：カフェのパスタ / 夜：冷凍チャーハン',
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
        'diary': '依頼人から、特定の出来事に関する証言を得た。それは昼、学校で図書館の自習室を初めて予約しレポートを書き上げた一件。依頼人はその出来事に対し「嬉しかった」と述べ、「静かで集中できてよかった」と評価した。当日の睡眠時間は6時間と記録されている。食事はおにぎり・学食のカレー・鍋を摂取し、運動は未実施。学習は実施済みであった。午前中は授業（統計学・線形代数）、午後は図書館での課題レポート作業、夜は夕食後すぐ就寝に時間を費やしていたことが確認された。',
        'answers': {
          'sleep': '6時間',
          'food': '朝：コンビニのおにぎり2個 / 昼：学食のカレー / 夜：鍋（一人）',
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
        'diary': '依頼人から、特定の出来事に関する証言を得た。それは昼、学校でPythonのgroupbyのバグをドキュメントをもとに解決した一件。依頼人はその出来事に対し「嬉しかった」と述べ、「やっと解決できてすっきりした」と評価した。当日の睡眠時間は7時間と記録されている。食事はヨーグルト・サンドイッチ・鶏むね肉の照り焼きを摂取し、運動は実施済み。学習も実施済みであった。午前中はプログラミング演習の授業、午後は研究室でのデバッグ作業、夜はジムでのランニングとストレッチに時間を費やしていたことが確認された。',
        'answers': {
          'sleep': '7時間',
          'food': '朝：ヨーグルト、バナナ / 昼：コンビニのサンドイッチ / 夜：鶏むね肉の照り焼き（自炊）',
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
        'diary': '依頼人から、特定の出来事に関する証言を得た。それは夜、居酒屋で友人とともに苦手なレバーを初めて完食した一件。依頼人はその出来事に対し「面白かった」と述べ、「不思議と食べられて自分でも驚いた」と評価した。当日の睡眠時間は5時間と記録されている。食事はファミレスのモーニング・居酒屋の唐揚げ・枝豆などを摂取し、運動は実施済み。学習も実施済みであった。午前中はオンライン講義（機械学習入門）の視聴、午後は近所の散歩と昼寝、夜は友人との居酒屋に時間を費やしていたことが確認された。',
        'answers': {
          'sleep': '5時間',
          'food': '朝：なし（寝坊）/ 昼：ファミレスのモーニング / 夜：居酒屋で唐揚げ・枝豆など',
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
        'diary': '依頼人から、特定の出来事に関する証言を得た。それは昼、学校でヒープを手書きで1から実装した一件。依頼人はその出来事に対し「嬉しかった」と述べ、「意外とすらすら書けて自信がついた」と評価した。当日の睡眠時間は8時間と記録されている。食事は食パン・学食の日替わり定食・コンビニのパスタを摂取し、運動は未実施。学習は実施済みであった。午前中は英語・データ構造の授業、午後は図書館での試験勉強、夜は入浴と読書に時間を費やしていたことが確認された。',
        'answers': {
          'sleep': '8時間',
          'food': '朝：食パン、目玉焼き / 昼：学食の日替わり定食 / 夜：コンビニのパスタ',
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
        'diary': '依頼人から、特定の出来事に関する証言を得た。それは夜、職場でバイト中に常連客へ自分から話しかけた一件。依頼人はその出来事に対し「嬉しかった」と述べ、「新メニューの感想を聞けてよかった」と評価した。当日の睡眠時間は6時間と記録されている。食事はカップ麺・学食のラーメン・まかないのカレーを摂取し、運動は未実施。学習は実施済みであった。午前中は確率論の授業と小テスト、午後はカフェでのアルバイト、夜は帰宅後シャワーを浴びて就寝に時間を費やしていたことが確認された。',
        'answers': {
          'sleep': '6時間',
          'food': '朝：コンビニのカップ麺 / 昼：学食のラーメン / 夜：アルバイト先でまかない（カレー）',
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
        'diary': '依頼人から、特定の出来事に関する証言を得た。それはプライベートな時間、自宅でFlutterとGemini APIを連携させAIアプリを初めて動かした一件。依頼人はその出来事に対し「嬉しかった」と述べ、「初めてAIが返答した瞬間は感動だった」と評価した。当日の睡眠時間は9時間と記録されている。食事はホットケーキ・デリバリーのピザ・カップ麺を摂取し、運動は未実施。学習は実施済みであった。午前中はゆっくり起床しYoutubeを見ながらストレッチ、午後はハッカソンの作業、夜はレビュー準備に時間を費やしていたことが確認された。',
        'answers': {
          'sleep': '9時間',
          'food': '朝：ホットケーキ / 昼：デリバリーのピザ / 夜：カップ麺',
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

    for (final entry in entries.entries) {
      await _db
          .collection('users')
          .doc(uid)
          .collection('entries')
          .doc(entry.key)
          .set({
        'diary': entry.value['diary'],
        'answers': entry.value['answers'],
        'numericAnswers': entry.value['numericAnswers'],
        'timestamp': FieldValue.serverTimestamp(),
      });
    }
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
