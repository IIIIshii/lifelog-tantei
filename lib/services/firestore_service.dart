import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/streak.dart';
import '../models/goal.dart';
import '../models/self_analysis.dart';
import 'package:flutter/foundation.dart';
import '../models/user_settings.dart';

// Firestoreへのデータ読み書きを担当するサービスクラス
class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ──────────────────────────────────────────────────────────────
  // コレクション参照
  //
  // パスをメソッドごとに直書きせず、ここに集約する。
  // 日記（entries）と目標の日々の記録（goals/{goalId}/entries）は
  // 同じ形のドキュメント（doc ID が 'YYYY-MM-DD'、answers / numericAnswers /
  // skipped を持つ）なので、下の _xxxIn 系ヘルパへ参照を渡して操作を共用する。
  // ──────────────────────────────────────────────────────────────
  DocumentReference<Map<String, dynamic>> _user(String uid) =>
      _db.collection('users').doc(uid);

  CollectionReference<Map<String, dynamic>> _entries(String uid) =>
      _user(uid).collection('entries');

  CollectionReference<Map<String, dynamic>> _goals(String uid) =>
      _user(uid).collection('goals');

  // 目標1件の日々の記録。日記の entries と同じ構成で、diary を持たないだけ。
  CollectionReference<Map<String, dynamic>> _goalEntries(
    String uid,
    String goalId,
  ) => _goals(uid).doc(goalId).collection('entries');

  // ──────────────────────────────────────────────────────────────
  // エントリの共用操作（日記・目標のどちらにも使う）
  // ──────────────────────────────────────────────────────────────

  // 直近 days 日の日付キー範囲（今日を含む）。
  // 日記と目標で同じ窓を使うため、計算をここに1本化している。
  ({String from, String to}) _recentRange(int days) {
    final now = DateTime.now();
    final from = now.subtract(Duration(days: days - 1));
    return (
      from: from.toIso8601String().split('T')[0],
      to: now.toIso8601String().split('T')[0],
    );
  }

  // 質問キー→回答のマップを書き込む（既存データとマージする）。
  // 3つとも空なら何も書かない（空のドキュメントを作らないため）。
  //
  // touchTimestamp は目標側だけ true にする。日記には saveDiary が時刻を残すが、
  // 目標には日記本文が無く、ここで残さないとドキュメントに時刻が一切入らない。
  Future<void> _saveAnswersIn(
    CollectionReference<Map<String, dynamic>> entries,
    String date,
    Map<String, String> answers, {
    Map<String, double>? numericAnswers,
    List<String>? skippedKeys,
    bool touchTimestamp = false,
  }) async {
    if (answers.isEmpty &&
        (numericAnswers == null || numericAnswers.isEmpty) &&
        (skippedKeys == null || skippedKeys.isEmpty)) {
      return;
    }
    final data = <String, dynamic>{};
    if (answers.isNotEmpty) data['answers'] = answers;
    if (numericAnswers != null && numericAnswers.isNotEmpty) {
      data['numericAnswers'] = numericAnswers;
    }
    if (skippedKeys != null && skippedKeys.isNotEmpty) {
      data['skipped'] = skippedKeys;
    }
    if (touchTimestamp) data['timestamp'] = FieldValue.serverTimestamp();
    await entries.doc(date).set(data, SetOptions(merge: true));
  }

  // 日付キーの範囲でエントリを取る。toKey を省くと fromKey 以降すべて。
  //
  // orderBy を使わないのは doc ID が 'YYYY-MM-DD' で範囲クエリだけで足りるため
  // （複合インデックスも要らない）。呼び出し側は順序に依存しない作りになっている。
  Future<List<MapEntry<String, Map<String, dynamic>>>> _entriesInRange(
    CollectionReference<Map<String, dynamic>> entries,
    String fromKey, {
    String? toKey,
  }) async {
    Query<Map<String, dynamic>> query = entries.where(
      FieldPath.documentId,
      isGreaterThanOrEqualTo: fromKey,
    );
    if (toKey != null) {
      query = query.where(FieldPath.documentId, isLessThanOrEqualTo: toKey);
    }
    final snap = await query.get();
    return snap.docs.map((doc) => MapEntry(doc.id, doc.data())).toList();
  }

  Future<List<MapEntry<String, Map<String, dynamic>>>> _allEntriesIn(
    CollectionReference<Map<String, dynamic>> entries,
  ) async {
    final snap = await entries.get();
    return snap.docs.map((doc) => MapEntry(doc.id, doc.data())).toList();
  }

  // 1日分のエントリ。ドキュメントが無ければ null。
  Future<Map<String, dynamic>?> _entryIn(
    CollectionReference<Map<String, dynamic>> entries,
    String date,
  ) async {
    final doc = await entries.doc(date).get();
    return doc.exists ? doc.data() : null;
  }

  Future<int> _messageCountIn(
    CollectionReference<Map<String, dynamic>> entries,
    String date,
  ) async {
    final snap = await entries
        .doc(date)
        .collection('conversation')
        .count()
        .get();
    return snap.count ?? 0;
  }

  Future<void> _saveMessageIn(
    CollectionReference<Map<String, dynamic>> entries,
    String date,
    String role,
    String text,
    int order,
  ) async {
    await entries.doc(date).collection('conversation').add({
      'role': role,
      'text': text,
      'order': order,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // 会話を order 順に読み出す。
  //
  // role / text だけを返すのは、呼び出し側（画面の _messages と MessageBubble）が
  // この形をそのまま使うため。timestamp は表示にも並べ替えにも使っていない
  // （order はクライアント採番で、保存順を再現する唯一の手がかり）。
  Future<List<Map<String, String>>> _messagesIn(
    CollectionReference<Map<String, dynamic>> entries,
    String date,
  ) async {
    final snap = await entries
        .doc(date)
        .collection('conversation')
        .orderBy('order')
        .get();
    return snap.docs.map((doc) {
      final data = doc.data();
      return {
        'role': data['role'] as String? ?? 'ai',
        'text': data['text'] as String? ?? '',
      };
    }).toList();
  }

  // ユーザーの設定をFirestoreから取得する（存在しなければデフォルト値を返す）
  Future<UserSettings> getUserSettings(String uid) async {
    final doc = await _db
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('preferences')
        .get();
    if (doc.exists && doc.data() != null) {
      final data = doc.data()!;
      final settings = UserSettings.fromMap(data);
      // customQuestionsが旧形式（インデックス依存）の場合、
      // 不変idを発行した新形式に変換して書き戻す（初回読み込み時に一度だけ実行）。
      // 書き戻しがオフライン等で失敗しても、既にメモリ上にある settings は
      // そのまま返す（設定読み込み自体を巻き添えで失敗させない）。
      // Firestore上のデータは旧形式のままなので、次回読み込み時に再度移行が試みられる。
      if (UserSettings.needsCustomQuestionsMigration(data)) {
        try {
          await saveUserSettings(uid, settings);
        } catch (e) {
          debugPrint('カスタム質問の移行書き戻しに失敗しました: $e');
        }
      }
      return settings;
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
    final data = await _entryIn(_entries(uid), date);
    return data?['diary'] as String?;
  }

  // 指定日の会話メッセージ数を返す（追記時のconversationOrderオフセット計算に使う）
  Future<int> getMessageCount(String uid, String date) =>
      _messageCountIn(_entries(uid), date);

  // 会話の1メッセージをFirestoreに保存する（順序orderで並び替えできるようにする）
  Future<void> saveMessage(
    String uid,
    String date,
    String role,
    String text,
    int order,
  ) => _saveMessageIn(_entries(uid), date, role, text, order);

  // 質問キー→回答テキストのマップをFirestoreに保存する（既存データとマージする）
  // numericAnswers が渡された場合は数値データも同時に保存する
  // skippedKeys が渡された場合は「質問したが未回答（スキップ）」のキー一覧も保存する
  Future<void> saveAnswers(
    String uid,
    String date,
    Map<String, String> answers, {
    Map<String, double>? numericAnswers,
    List<String>? skippedKeys,
  }) => _saveAnswersIn(
    _entries(uid),
    date,
    answers,
    numericAnswers: numericAnswers,
    skippedKeys: skippedKeys,
  );

  // 直近 days 日分のエントリを日付文字列とデータのペアで返す
  Future<List<MapEntry<String, Map<String, dynamic>>>> getRecentEntries(
    String uid,
    int days,
  ) {
    final range = _recentRange(days);
    return _entriesInRange(_entries(uid), range.from, toKey: range.to);
  }

  // 生成した日記テキストをFirestoreに保存する（既存データとマージする）
  //
  // 目標側に同じものを用意しないのは、目標の記録に日記本文が無いため
  // （追跡の記録は answers と会話ログだけで足り、文面は生成も保存もしない）。
  Future<void> saveDiary(
    String uid,
    String date,
    String diary, {
    String? mode,
  }) async {
    final data = <String, dynamic>{
      'diary': diary,
      'timestamp': FieldValue.serverTimestamp(),
    };
    if (mode != null) data['diaryMode'] = mode;
    await _entries(uid).doc(date).set(data, SetOptions(merge: true));
  }

  // デモ用のモックデータを14日分Firestoreに書き込む。
  // 日付は固定せず、今日を基準に「13日前〜今日」へ動的に割り当てるため、
  // 直近エントリ表示やAI分析（直近14日参照）にも必ずデモデータが反映される。
  // あわせて、回答キー（custom_* や sleep など）と矛盾しないよう設定
  // （カスタム質問・記録トグル）も投入し「設定済みの状態」を再現する。
  Future<void> seedMockData(String uid) async {
    // 回答キーに対応する記録項目を有効化し、カスタム質問2問を設定済みにする。
    // モデルの toMap() を再利用し、フィールド定義の二重管理を避ける。
    // idは以下のモックエントリの回答キー（custom_mock-q1等）と対応させる固定値。
    const demoSettings = UserSettings(
      recordEvent: true,
      recallAssist: true,
      recordSleep: true,
      recordFood: true,
      recordExercise: true,
      recordStudy: true,
      customQuestions: [
        CustomQuestion(id: 'mock-q1', text: '今日、心が動く瞬間はあった？'),
        CustomQuestion(id: 'mock-q2', text: '今日、初めて・新しく挑戦したことは？'),
      ],
      selectedRole: 'hardboiled',
    );
    await saveUserSettings(uid, demoSettings);

    // 古い順（13日前→今日）に並べたエントリ列。doc IDは投入時に動的生成する。
    final entries = <Map<String, dynamic>>[
      {
        'diary':
            '七時間の睡眠で一日が明けた。午前を洗濯と部屋の片付けに充てた依頼人は、昼下がり、近所のカフェにいた。読書の手を止め、ふと思い立って注文をすべて英語で通したという。店員はごく自然に応じ、拍子抜けするほど呆気なく事は済んだ。本人は「面白かった」とだけ漏らしている。夜は友人とのオンラインゲーム。体も頭も程よく動かした一日だったことが確認された。',
        'answers': {
          'sleep': '7時間',
          'food': 'カフェのパスタ',
          'exercise': 'した',
          'study': 'した',
          'custom_mock-q1': 'はい',
          'custom_mock-q2': 'カフェで初めてオーダーを全部英語でしてみた',
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
      {
        'diary':
            '六時間の睡眠。午前は統計学と線形代数の講義で埋まっていた。昼、依頼人は学内の図書館へ向かう。初めて自習室を予約し、その一室にこもったという。静寂が思考を運び、停滞していたレポートは一気に最後まで書き上がった。本人は「集中できた」と手応えを語っている。夕食を済ませると糸が切れたように眠りに落ちたことが記録されている。短い夜だったが、机の上の達成は確かだ。',
        'answers': {
          'sleep': '6時間',
          'food': '学食のカレー',
          'exercise': 'していない',
          'study': 'した',
          'custom_mock-q1': 'はい',
          'custom_mock-q2': '図書館の自習室を初めて予約して使った',
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
      {
        'diary':
            '午前のプログラミング演習を終え、依頼人は研究室にこもった。午後いっぱいを費やした相手は、pandasのgroupbyに潜む一つのバグ。ドキュメントを丹念に読み返すうち、原因はようやく姿を現したという。長く追い続けた糸口がほどけた瞬間、本人は「すっきりした」と短く息を吐いた。夜はジムでランニングとストレッチ。自炊の鶏むね肉で締めた一日は、頭も体も使い切ったことが確認された。睡眠は七時間。',
        'answers': {
          'sleep': '7時間',
          'food': '鶏むね肉の照り焼き（自炊）',
          'exercise': 'した',
          'study': 'した',
          'custom_mock-q1': 'はい',
          'custom_mock-q2': 'pandasのgroupbyを初めて使いこなせた',
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
      {
        'diary':
            '睡眠は五時間と短い。午前は機械学習入門のオンライン講義に充て、午後は近所を三十分歩いてから昼寝で体を整えたという。夜、依頼人は友人に誘われ居酒屋の席に着いた。長らく苦手としてきたレバーが運ばれてくる。意を決して口に運ぶと、不思議と箸が止まらず、ついには完食。本人も「自分でも驚いた」と面白がっている。唐揚げと枝豆を囲んだ賑やかな夜だったことが記録されている。',
        'answers': {
          'sleep': '5時間',
          'food': '居酒屋',
          'exercise': 'した',
          'study': 'した',
          'custom_mock-q1': 'はい',
          'custom_mock-q2': '居酒屋で苦手なレバーを初めて完食できた',
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
      {
        'diary':
            '八時間の睡眠が、この日の冴えを支えていたのかもしれない。午前は英語とデータ構造の講義。その流れのまま、午後の図書館で依頼人は試験勉強に没頭した。ふと、習ったばかりのヒープを何も見ずに一から書き起こしてみたという。手は驚くほど滑らかに動き、コードは淀みなく組み上がった。「自信がついた」と本人は手応えを口にしている。帰宅後は入浴と読書で静かに一日を閉じたことが確認された。',
        'answers': {
          'sleep': '8時間',
          'food': '日替わり定食',
          'exercise': 'していない',
          'study': 'した',
          'custom_mock-q1': 'はい',
          'custom_mock-q2': 'ヒープの実装を手書きで1から書いてみた',
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
      {
        'diary':
            '六時間の睡眠で迎えた朝は、確率論の講義と小テストから始まった。午後四時、依頼人はカフェの制服に袖を通す。閉店までの五時間、いつもは言葉少なに皿を運ぶだけの本人が、この日は常連客へ自ら声をかけたという。新メニューの感想を尋ねると、相手は思いのほか饒舌に語ってくれた。「聞いてよかった」と本人は嬉しげだ。まかないのカレーで腹を満たし、帰宅後はシャワーを浴びて床に就いたことが記録されている。',
        'answers': {
          'sleep': '6時間',
          'food': 'アルバイト先でまかない（カレー）',
          'exercise': 'していない',
          'study': 'した',
          'custom_mock-q1': 'はい',
          'custom_mock-q2': 'バイト中に常連さんから新メニューの感想を自分から聞いてみた',
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
      {
        'diary':
            '九時間。たっぷりの睡眠から始まった休日だった。午前はYoutubeを横目にストレッチで体をほぐし、ホットケーキで遅い朝食を取ったという。午後からはハッカソンの開発に没頭。FlutterにGemini APIをつなぎ込む作業が、夜になってついに実を結んだ。画面の向こうでAIが初めて返答を寄こした瞬間、依頼人は「感動した」と声を弾ませている。デリバリーのピザで祝杯をあげ、レビューの準備まで手をつけたことが確認された。',
        'answers': {
          'sleep': '9時間',
          'food': 'デリバリーのピザ',
          'exercise': 'していない',
          'study': 'した',
          'custom_mock-q1': 'はい',
          'custom_mock-q2': 'Gemini APIを使ったアプリを初めて動かせた',
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
      {
        'diary':
            '夜明け前、まだ街が眠るうちに依頼人は布団を抜け出した。七時間の睡眠で目覚めは軽い。向かった先は近所の公園。これまで縁のなかった早朝のランニングに、思い切って足を踏み出したという。澄んだ空気と人気のない並木道は、想像していたよりずっと心地よかったらしい。「面白かった」と本人は息を弾ませている。午後はアルゴリズムの講義に出席し、鮭の塩焼きで夕食を済ませると、いつもより早く床に就いたことが記録されている。',
        'answers': {
          'sleep': '7時間',
          'food': '鮭の塩焼き（自炊）',
          'exercise': 'した',
          'study': 'していない',
          'custom_mock-q1': 'はい',
          'custom_mock-q2': '思い切って早朝ランニングを始めてみた',
          'morning': '早起きして近所の公園を走った',
          'afternoon': '授業（アルゴリズム）',
          'evening': '早めに就寝',
          'event_when': '朝',
          'event_where': '公園',
          'event_who': '自分',
          'event_what': '初めて早起きして公園を走ってみた',
          'event_how': '面白かった',
        },
        'numericAnswers': {'sleep': 7.0},
      },
      {
        'diary':
            '六時間の睡眠。午前から依頼人はスライドの最終確認に余念がなかった。迎えた午後、研究室の輪講。初めて発表者の側に立った本人は、用意してきた論文の要点を一つずつ言葉にしていったという。質疑にも詰まることなく応じ、終えたときには大役を果たした実感が残った。「やりきった」と本人は晴れやかだ。夜は友人との通話でささやかな打ち上げ。張り詰めた一日を、笑い声で締めくくったことが確認された。',
        'answers': {
          'sleep': '6時間',
          'food': '学食の定食',
          'exercise': 'していない',
          'study': 'した',
          'custom_mock-q1': 'はい',
          'custom_mock-q2': '研究室の輪講で初めて発表を担当した',
          'morning': '発表スライドの最終確認',
          'afternoon': '研究室の輪講で初めて発表した',
          'evening': '友人と通話で打ち上げ',
          'event_when': '昼',
          'event_where': '学校',
          'event_who': '自分',
          'event_what': '研究室の輪講で初めて発表を担当しきった',
          'event_how': '嬉しかった',
        },
        'numericAnswers': {'sleep': 6.0},
      },
      {
        'diary':
            '七時間の睡眠で迎えた一日は、微分積分の講義から動き出した。午後は課題と読書に費やし、帰路、依頼人はふと路地裏の古本屋に立ち寄ったという。棚を端から目で追っていた指が、一冊で止まる。長く探し続けていた絶版の数学書が、そこに静かに収まっていた。「まさかここで」と本人は声を漏らしている。思わぬ巡り合わせを抱えて家路についた夜だった。よく歩き、よく学んだ一日だったことが記録されている。',
        'answers': {
          'sleep': '7時間',
          'food': 'カフェのサンドイッチ',
          'exercise': 'した',
          'study': 'した',
          'custom_mock-q1': 'はい',
          'custom_mock-q2': '長く探していた絶版の数学書を古本屋で手に入れた',
          'morning': '授業（微分積分）',
          'afternoon': '課題と読書',
          'evening': '帰り道に古本屋へ立ち寄った',
          'event_when': '夜',
          'event_where': '古本屋',
          'event_who': '自分',
          'event_what': 'ずっと探していた絶版の数学書を古本屋で見つけた',
          'event_how': '嬉しかった',
        },
        'numericAnswers': {'sleep': 7.0},
      },
      {
        'diary':
            '終日の雨。八時間眠った依頼人は、雨音を聞きながらの二度寝という贅沢から一日を始めたという。午後は録りためた番組をゆっくりと消化。これといった予定のない、静かな休日だった。夜になり、本人はかねて気になっていたスパイスからのカレー作りに腰を据える。慣れない計量と火加減に手こずりながらも、台所には次第に本格的な香りが立ち込めていった。「面白かった」と本人。雨の一日を、湯気の向こうで締めくくったことが確認された。',
        'answers': {
          'sleep': '8時間',
          'food': 'スパイスから作ったカレー',
          'exercise': 'していない',
          'study': 'していない',
          'custom_mock-q1': 'いいえ',
          'custom_mock-q2': 'スパイスを調合して一からカレーを作ってみた',
          'morning': '雨音を聞きながら二度寝',
          'afternoon': '録画した番組をゆっくり消化',
          'evening': 'スパイスからカレー作りに挑戦',
          'event_when': 'プライベート',
          'event_where': '自宅',
          'event_who': '自分',
          'event_what': 'スパイスから一通り揃えてカレーを作ってみた',
          'event_how': '面白かった',
        },
        'numericAnswers': {'sleep': 8.0},
      },
      {
        'diary':
            '六時間の睡眠で始まった一日は、線形代数の講義と図書館での予習で過ぎていった。夜、依頼人はアルバイト先のカフェに立つ。閉店後、店長から初めてレジ締めを任されたという。売上を数え、帳簿と突き合わせる一連の作業を、同僚に教わりながら最後までやり遂げた。数字がぴたりと合ったとき、信頼されている手応えが胸に残ったらしい。「任せてもらえて嬉しかった」と本人。まかないで腹を満たし、夜道を帰っていったことが記録されている。',
        'answers': {
          'sleep': '6時間',
          'food': 'アルバイト先のまかない',
          'exercise': 'していない',
          'study': 'した',
          'custom_mock-q1': 'はい',
          'custom_mock-q2': 'バイトで初めてレジ締めを任された',
          'morning': '授業（線形代数）',
          'afternoon': '図書館で予習',
          'evening': 'カフェのアルバイトで初めてレジ締めをした',
          'event_when': '夜',
          'event_where': '職場',
          'event_who': '同僚と',
          'event_what': 'アルバイトで初めて閉店後のレジ締めを任された',
          'event_how': '嬉しかった',
        },
        'numericAnswers': {'sleep': 6.0},
      },
      {
        'diary':
            '五時間の睡眠で迎えた朝、確率統計の講義までは穏やかに進んでいた。事は午後に起きる。作りかけていたプレゼン資料が、保存の手違いで消えていたという。依頼人は気を取り直し、記憶を頼りに一から組み直す作業へ取りかかった。手は止めず、夕方までに資料はかつての形を取り戻していった。夜には同じことを繰り返さぬよう、クラウドへの自動バックアップを設定したと本人は語っている。教訓を一つ手にした一日だったことが記録されている。',
        'answers': {
          'sleep': '5時間',
          'food': '学食のカレー',
          'exercise': 'していない',
          'study': 'した',
          'custom_mock-q1': 'いいえ',
          'custom_mock-q2': 'クラウドへの自動バックアップを設定した',
          'morning': '授業（確率統計）',
          'afternoon': '消えたプレゼン資料を作り直した',
          'evening': 'バックアップ環境を見直した',
          'event_when': '昼',
          'event_where': '学校',
          'event_who': '自分',
          'event_what': '作りかけのプレゼン資料が消え、一から作り直すことになった',
          'event_how': '怒った',
        },
        'numericAnswers': {'sleep': 5.0},
      },
      {
        'diary':
            '九時間眠ってもなお、体はまだ本調子ではなかったらしい。喉に違和感を覚えた依頼人は、この日の予定をすべて切り上げ、休養に充てると決めたという。午前はおかゆで胃を温め、午後は録りためていた映画をゆっくりと観て過ごした。動き回らず、ただ体の声に耳を澄ませる一日。夜は早々に床へ入っている。立ち止まることもまた、明日へ向けた支度なのだろう。無理をしなかった一日として記録されている。',
        'answers': {
          'sleep': '9時間',
          'food': 'おかゆ',
          'exercise': 'していない',
          'study': 'していない',
          'custom_mock-q1': 'いいえ',
          'custom_mock-q2': '体調を優先して一日きちんと休むと決めた',
          'morning': '体調を整えるため終日休養',
          'afternoon': '録画していた映画を観た',
          'evening': '早めに就寝',
          'event_when': 'プライベート',
          'event_where': '自宅',
          'event_who': '自分',
          'event_what': '風邪気味で予定を切り上げ、一日ゆっくり休んだ',
          'event_how': '悲しかった',
        },
        'numericAnswers': {'sleep': 9.0},
      },
    ];

    // entries[0] が13日前、entries[last] が今日になるよう日付を割り当てる
    final today = DateTime.now();
    for (var i = 0; i < entries.length; i++) {
      final date = today.subtract(Duration(days: entries.length - 1 - i));
      final dateStr = date.toIso8601String().split('T')[0]; // YYYY-MM-DD
      final entry = entries[i];
      await _db
          .collection('users')
          .doc(uid)
          .collection('entries')
          .doc(dateStr)
          .set({
            'diary': entry['diary'],
            'answers': entry['answers'],
            'numericAnswers': entry['numericAnswers'],
            'timestamp': FieldValue.serverTimestamp(),
          });
    }
  }

  // 全エントリを日付の降順で返す（CSVエクスポート用）
  Future<List<MapEntry<String, Map<String, dynamic>>>> getAllEntries(
    String uid,
  ) async {
    final entries = await _allEntriesIn(_entries(uid));
    entries.sort((a, b) => b.key.compareTo(a.key));
    return entries;
  }

  // 日記エントリ一覧を取得するクエリを返す
  // ソートはクライアント側でドキュメントID（YYYY-MM-DD）の降順で行う
  Query<Map<String, dynamic>> entriesQuery(String uid) => _entries(uid);

  // 最新のAI所見キャッシュを取得する（未生成なら null を返す）
  // ドキュメントは {text, generatedAt, periodDays} の形式で保存される
  Future<Map<String, dynamic>?> getLatestAnalysis(String uid) async {
    final doc = await _db
        .collection('users')
        .doc(uid)
        .collection('analyses')
        .doc('latest')
        .get();
    if (doc.exists) return doc.data();
    return null;
  }

  // AI所見テキストを analyses/latest に上書き保存する
  Future<void> saveAnalysis(String uid, String text) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('analyses')
        .doc('latest')
        .set({
          'text': text,
          'periodDays': 14,
          'generatedAt': FieldValue.serverTimestamp(),
        });
  }

  // 今日のAIコメントキャッシュを取得する（未生成なら null を返す）
  Future<Map<String, dynamic>?> getTodayComment(String uid) async {
    final doc = await _db
        .collection('users')
        .doc(uid)
        .collection('analyses')
        .doc('today')
        .get();
    if (doc.exists) return doc.data();
    return null;
  }

  // 今日のAIコメントを analyses/today に上書き保存する
  Future<void> saveTodayComment(String uid, String text) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('analyses')
        .doc('today')
        .set({'text': text, 'generatedAt': FieldValue.serverTimestamp()});
  }

  // ユーザーの自己分析（MBTI等）を取得する（存在しなければデフォルト＝未登録を返す）
  // 保存先を settings/preferences と分けているのは、記録の設定ではなく依頼人本人の属性であり、
  // 今後 MBTI 以外の項目を足していく前提のため。
  Future<SelfAnalysis> getSelfAnalysis(String uid) async {
    final doc = await _db
        .collection('users')
        .doc(uid)
        .collection('self-analysis')
        .doc('profile')
        .get();
    if (doc.exists && doc.data() != null) {
      return SelfAnalysis.fromMap(doc.data()!);
    }
    return SelfAnalysis.defaults();
  }

  // ユーザーの自己分析をFirestoreに保存する
  Future<void> saveSelfAnalysis(String uid, SelfAnalysis selfAnalysis) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('self-analysis')
        .doc('profile')
        .set(selfAnalysis.toMap());
  }

  // 追跡中の目標を新しい順で返す。1件も無ければ空リスト。
  //
  // 保存先を goals/{goalId} の複数ドキュメントにしたのは、追う事件を
  // kMaxTrackedGoals 件まで同時に持てるようにしたため。
  //
  // 追跡を終えたものは読まない（status で分かるが、ここでは捨てる）。
  // goal-archive の移行も行わない ―― 解決済みを画面に出す相談室ハブだけが
  // getAllGoals を呼び、そこで一度きりの引き上げを済ませる。
  // ホーム・分析室・相談室の各画面が毎回 archive を読むのは無駄なため。
  Future<List<Goal>> getGoals(String uid) async => (await _readGoals(uid)).active;

  // 追跡中と追跡を終えたものを、1回の読み取りで分けて返す。
  // 旧 goal-archive が残っていればここで goals へ引き上げる（下記 _migrateArchivedGoals）。
  Future<({List<Goal> active, List<Goal> closed})> getAllGoals(
    String uid,
  ) async {
    final divided = await _readGoals(uid);
    final closed = [...divided.closed];
    try {
      closed.addAll(await _migrateArchivedGoals(uid));
    } catch (e) {
      // 読めなくても追跡中の目標は返す（解決済みの棚が空になるだけで済ませる）
      debugPrint('解決済みの目標の読み込みに失敗しました: $e');
    }
    closed.sort(Goal.byClosedDesc);
    return (active: divided.active, closed: closed);
  }

  // goals コレクションを読んで status で振り分ける。
  //
  // 旧スキーマ（アクティブな目標が常に1件で goals/current に置いていた頃）の
  // ドキュメントが残っていれば、ここで goals/{goalId} へ移して current を消す。
  // 一度きりの移行スクリプトを書かず読み取りのついでで済ませるのは、
  // getUserSettings のカスタム質問の移行と同じ流儀
  // （書き戻しが失敗しても読み込み自体は成功させ、次回の読み込みでまた試す）。
  //
  // 並べ替えをクエリの orderBy ではなく取得後に行うのは、createdAt を持たない
  // 古いドキュメントが orderBy では結果から落ちてしまうため。
  Future<({List<Goal> active, List<Goal> closed})> _readGoals(
    String uid,
  ) async {
    final snapshot = await _goals(uid).get();

    final divided = partitionGoalDocs(
      snapshot.docs.map((doc) => MapEntry(doc.id, doc.data())),
    );

    final active = [...divided.active];
    final legacy = divided.legacy;
    if (legacy != null) {
      // 移行が失敗しても、読み込んだ内容はそのまま画面に出す
      active.add(legacy);
      try {
        await _migrateLegacyGoal(uid, legacy);
      } catch (e) {
        debugPrint('旧形式の目標の移行に失敗しました: $e');
      }
    }

    active.sort(Goal.byNewest);
    return (active: active, closed: divided.closed);
  }

  // goals/current を goals/{goalId} へ移し替える。
  // 書き込みと削除をまとめるのは、片方だけ通ると同じ目標が2件に見えるため。
  Future<void> _migrateLegacyGoal(String uid, Goal goal) async {
    final goals = _goals(uid);
    final batch = _db.batch();
    batch.set(goals.doc(goal.id), goal.toMap());
    batch.delete(goals.doc(kLegacyGoalDocId));
    await batch.commit();
  }

  // 旧 goal-archive のドキュメントを goals/{goalId} へ status 付きで引き上げる。
  //
  // 追跡を終えた目標をドキュメントごと別コレクションへ移す方式をやめたのは、
  // 目標が配下に日々の記録（entries サブコレクション）を持つようになったため。
  // Firestore はドキュメントを移してもサブコレクションを運ばないので、
  // 移す方式では解決した事件の記録が置き去りになる。
  //
  // 読めたものは書き戻しの成否にかかわらず返す（getUserSettings のカスタム質問移行と
  // 同じ流儀）。書き込みと削除を WriteBatch でまとめるのは、片方だけ通ると
  // 同じ事件が解決済みの棚に二重で出るため。
  Future<List<Goal>> _migrateArchivedGoals(String uid) async {
    final snapshot = await _user(uid).collection('goal-archive').get();
    if (snapshot.docs.isEmpty) return const [];

    final goals = <Goal>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      // Timestamp から日付文字列への変換はここだけの仕事。
      // モデル側を cloud_firestore に依存させないため。
      final archivedAt = (data['archivedAt'] as Timestamp?)?.toDate();
      final goal = goalFromArchiveDoc(
        doc.id,
        data,
        closedAt: archivedAt == null ? '' : dateKey(archivedAt),
      );
      if (goal.isEmpty) continue;
      goals.add(goal);
    }
    if (goals.isEmpty) return goals;

    try {
      final batch = _db.batch();
      for (final goal in goals) {
        batch.set(_goals(uid).doc(goal.id), goal.toMap());
      }
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      debugPrint('解決済みの目標の移行書き戻しに失敗しました: $e');
    }
    return goals;
  }

  // 目標1件を保存する（既存の内容を丸ごと置き換える）。
  // ドキュメントIDに Goal.id を使うので、見直しで同じ id のまま保存すれば
  // 上書きになり、新しい id なら1件増える。
  // id が空のまま呼ぶと Firestore は空のドキュメントIDで落ちる。
  // 何が起きたのか分かる形で先に止める。
  //
  // set() の全置換でも配下の entries サブコレクションは消えない
  // （Firestore はドキュメントのフィールドだけを置き換える）ので、
  // 見立てを見直しても日々の記録は残る。
  Future<void> saveGoal(String uid, Goal goal) async {
    if (goal.id.isEmpty) {
      throw ArgumentError.value(goal.id, 'goal.id', '目標のIDが空です');
    }
    await _goals(uid).doc(goal.id).set(goal.toMap());
  }

  // 目標の追跡を終える。ドキュメントは移さず status と closedAt を書き換えるだけ。
  //
  // 配下の記録（entries サブコレクション）をそのまま残すための方式。
  // closedAt は 'YYYY-MM-DD'（呼び出し側が dateKey で渡す）。
  // 未設定・id を持たないものは何もしない（空のドキュメントが増えるだけのため）。
  Future<void> closeGoal(
    String uid,
    Goal goal,
    GoalStatus status, {
    required String closedAt,
  }) async {
    if (goal.isEmpty || goal.id.isEmpty) return;
    await _goals(uid).doc(goal.id).set({
      'status': goalStatusTo(status),
      'closedAt': closedAt,
    }, SetOptions(merge: true));
  }

  // ──────────────────────────────────────────────────────────────
  // 目標の日々の記録（goals/{goalId}/entries/{YYYY-MM-DD}）
  //
  // 日記のエントリと同じ形にしているので、lib/core/goal_progress.dart の
  // 達成率・最新値の計算をそのまま通せる（回答キーも 'goal_<actionId>' のまま）。
  // 日記本文に相当するものは持たない。
  // ──────────────────────────────────────────────────────────────

  Future<void> saveGoalAnswers(
    String uid,
    String goalId,
    String date,
    Map<String, String> answers, {
    Map<String, double>? numericAnswers,
    List<String>? skippedKeys,
  }) => _saveAnswersIn(
    _goalEntries(uid, goalId),
    date,
    answers,
    numericAnswers: numericAnswers,
    skippedKeys: skippedKeys,
    // 日記と違ってこのコレクションには saveDiary が来ないため、
    // ここで時刻を残さないとドキュメントに一切入らない
    touchTimestamp: true,
  );

  // 直近 days 日分（分析室の窓に合わせるとき用）
  Future<List<MapEntry<String, Map<String, dynamic>>>> getRecentGoalEntries(
    String uid,
    String goalId,
    int days,
  ) {
    final range = _recentRange(days);
    return _entriesInRange(
      _goalEntries(uid, goalId),
      range.from,
      toKey: range.to,
    );
  }

  // fromKey 以降すべて（記録一覧が着手日から辿るとき用）。
  // 上限を付けないのは、未来日付のエントリが作られないため。
  Future<List<MapEntry<String, Map<String, dynamic>>>> getGoalEntriesSince(
    String uid,
    String goalId,
    String fromKey,
  ) => _entriesInRange(_goalEntries(uid, goalId), fromKey);

  // 指定日のエントリを目標ごとに引く（記録が無い目標はキーごと入らない）。
  //
  // 追跡中は最大 kMaxTrackedGoals 件なので、並行の単発読みで足りる。
  // collectionGroup('entries') を使わないのは、日記の entries と同名でぶつかり
  // 日記エントリまで拾ってしまうため。
  Future<Map<String, Map<String, dynamic>>> getGoalEntriesOn(
    String uid,
    Iterable<String> goalIds,
    String date,
  ) async {
    final ids = goalIds.toList(growable: false);
    if (ids.isEmpty) return const {};
    final entries = await Future.wait(
      ids.map((id) => _entryIn(_goalEntries(uid, id), date)),
    );
    final result = <String, Map<String, dynamic>>{};
    for (var i = 0; i < ids.length; i++) {
      final data = entries[i];
      if (data != null) result[ids[i]] = data;
    }
    return result;
  }

  Future<int> getGoalMessageCount(String uid, String goalId, String date) =>
      _messageCountIn(_goalEntries(uid, goalId), date);

  Future<void> saveGoalMessage(
    String uid,
    String goalId,
    String date,
    String role,
    String text,
    int order,
  ) => _saveMessageIn(_goalEntries(uid, goalId), date, role, text, order);

  // その日の会話を order 順で返す。記録一覧から1日分を読み返すために使う。
  Future<List<Map<String, String>>> getGoalConversation(
    String uid,
    String goalId,
    String date,
  ) => _messagesIn(_goalEntries(uid, goalId), date);
}
