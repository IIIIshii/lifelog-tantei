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
        'diary': '日曜日は家の掃除から始まった。午後はカフェで読書。初めて注文を英語でしてみたが、店員さんが普通に対応してくれて少し拍子抜け。夜は友人とゲームで盛り上がり、気づけば23時を過ぎていた。',
        'answers': {
          'morning': '洗濯と部屋の掃除をした',
          'afternoon': '近所のカフェで本を読んだ',
          'evening': '友人とオンラインゲームをした',
          'sleep': '7時間',
          'food': '朝：トースト、卵焼き / 昼：カフェのパスタ / 夜：冷凍チャーハン',
          'exercise': 'ジョギング20分',
          'study': '英単語を50個復習した',
          'custom_0': 'いいえ',
          'custom_1': 'カフェで初めてオーダーを全部英語でしてみた',
        },
        'numericAnswers': {'sleep': 7.0},
      },
      '2026-03-09': {
        'diary': '月曜は授業が詰まっている。午後は図書館の自習室を初めて予約してレポートを書き上げた。静かで集中できてよかった。夜は鍋を作ったものの、疲れて早々に就寝。',
        'answers': {
          'morning': '授業（統計学・線形代数）',
          'afternoon': '図書館で課題レポートを書いた',
          'evening': '夕食後すぐ寝てしまった',
          'sleep': '6時間',
          'food': '朝：コンビニのおにぎり2個 / 昼：学食のカレー / 夜：鍋（一人）',
          'exercise': 'なし',
          'study': '統計学の課題レポート（仮説検定の章）',
          'custom_0': 'はい',
          'custom_1': '図書館の自習室を初めて予約して使った',
        },
        'numericAnswers': {'sleep': 6.0},
      },
      '2026-03-10': {
        'diary': '午後は研究室でPythonのバグと格闘。groupbyでつまずいていたが、ドキュメントを読み込んでついに解決。夜はジムでランニング。体を動かすとやはり気分がすっきりする。',
        'answers': {
          'morning': '授業（プログラミング演習）',
          'afternoon': '研究室でPythonのデバッグ作業',
          'evening': 'ジムでランニングとストレッチ',
          'sleep': '7時間',
          'food': '朝：ヨーグルト、バナナ / 昼：コンビニのサンドイッチ / 夜：鶏むね肉の照り焼き（自炊）',
          'exercise': 'ランニング30分・ストレッチ15分',
          'study': 'Pythonのpandasライブラリ（groupbyの使い方）',
          'custom_0': 'いいえ',
          'custom_1': 'pandasのgroupbyを初めて使いこなせた',
        },
        'numericAnswers': {'sleep': 7.0},
      },
      '2026-03-11': {
        'diary': '寝坊してファミレスモーニングからスタート。午後は散歩と昼寝でゆるやかに過ごし、夜は友人と久々に外食。居酒屋で苦手なレバーを出されたが、今日は不思議と食べられた。',
        'answers': {
          'morning': 'オンライン講義（機械学習入門）の視聴',
          'afternoon': '近所を30分散歩してから昼寝',
          'evening': '友人と居酒屋に行った',
          'sleep': '5時間',
          'food': '朝：なし（寝坊）/ 昼：ファミレスのモーニング / 夜：居酒屋で唐揚げ・枝豆など',
          'exercise': '散歩30分',
          'study': '機械学習の決定木アルゴリズム（動画2本分）',
          'custom_0': 'いいえ',
          'custom_1': '居酒屋で苦手なレバーを初めて完食できた',
        },
        'numericAnswers': {'sleep': 5.0},
      },
      '2026-03-12': {
        'diary': '木曜は図書館でデータ構造の勉強に集中した日。ヒープを手書きで実装してみたら意外とすらすら書けて自信がついた。夜は早めに切り上げてゆっくり休んだ。',
        'answers': {
          'morning': '授業（英語・データ構造）',
          'afternoon': '図書館で試験勉強',
          'evening': '帰宅後すぐ入浴・読書',
          'sleep': '8時間',
          'food': '朝：食パン、目玉焼き / 昼：学食の日替わり定食 / 夜：コンビニのパスタ',
          'exercise': 'なし',
          'study': 'データ構造（ヒープ・優先度付きキュー）の試験対策',
          'custom_0': 'はい',
          'custom_1': 'ヒープの実装を手書きで1から書いてみた',
        },
        'numericAnswers': {'sleep': 8.0},
      },
      '2026-03-13': {
        'diary': '金曜は小テストとバイトで慌ただしかった。まかないのカレーが美味しくて疲れが吹っ飛んだ。帰宅後は即就寝。体力の限界だった。',
        'answers': {
          'morning': '授業（確率論）・小テスト',
          'afternoon': 'カフェでアルバイト（16〜21時）',
          'evening': '帰宅後シャワーを浴びて就寝',
          'sleep': '6時間',
          'food': '朝：コンビニのカップ麺 / 昼：学食のラーメン / 夜：アルバイト先でまかない（カレー）',
          'exercise': 'なし',
          'study': '授業中に確率論の復習ノートを整理した',
          'custom_0': 'いいえ',
          'custom_1': 'バイト中に常連さんから新メニューの感想を自分から聞いてみた',
        },
        'numericAnswers': {'sleep': 6.0},
      },
      '2026-03-14': {
        'diary': '土曜日はハッカソンデー。午後からFlutterとGemini APIの連携に取り組み、ついにAIが返答するところまで動いた。ピザで英気を養いながら夜まで集中。初めてAIアプリが動いた瞬間は感動だった。',
        'answers': {
          'morning': 'ゆっくり起床・Youtubeを見ながらストレッチ',
          'afternoon': 'ハッカソンの作業（Flutterアプリ開発）',
          'evening': '作業の続き・レビュー準備',
          'sleep': '9時間以上',
          'food': '朝：ホットケーキ / 昼：デリバリーのピザ / 夜：カップ麺',
          'exercise': 'ストレッチ10分',
          'study': 'FlutterとFirestoreの連携・Gemini APIの使い方',
          'custom_0': 'いいえ',
          'custom_1': 'Gemini APIを使ったアプリを初めて動かせた',
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
