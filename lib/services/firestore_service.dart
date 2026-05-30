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

  // デモ用のモックデータを14日分Firestoreに書き込む。
  // 日付は固定せず、今日を基準に「13日前〜今日」へ動的に割り当てるため、
  // 直近エントリ表示やAI分析（直近14日参照）にも必ずデモデータが反映される。
  // あわせて、回答キー（custom_* や sleep など）と矛盾しないよう設定
  // （カスタム質問・記録トグル）も投入し「設定済みの状態」を再現する。
  Future<void> seedMockData(String uid) async {
    // 回答キーに対応する記録項目を有効化し、カスタム質問2問を設定済みにする。
    // モデルの toMap() を再利用し、フィールド定義の二重管理を避ける。
    const demoSettings = UserSettings(
      recordEvent: true,
      recallAssist: true,
      recordSleep: true,
      recordFood: true,
      recordExercise: true,
      recordStudy: true,
      customQuestions: [
        '今日、心が動く瞬間はあった？',
        '今日、初めて・新しく挑戦したことは？',
      ],
      selectedRole: 'hardboiled',
    );
    await saveUserSettings(uid, demoSettings);

    // 古い順（13日前→今日）に並べたエントリ列。doc IDは投入時に動的生成する。
    final entries = <Map<String, dynamic>>[
      {
        'diary': '七時間の睡眠で一日が明けた。午前を洗濯と部屋の片付けに充てた依頼人は、昼下がり、近所のカフェにいた。読書の手を止め、ふと思い立って注文をすべて英語で通したという。店員はごく自然に応じ、拍子抜けするほど呆気なく事は済んだ。本人は「面白かった」とだけ漏らしている。夜は友人とのオンラインゲーム。体も頭も程よく動かした一日だったことが確認された。',
        'answers': {
          'sleep': '7時間',
          'food': 'カフェのパスタ',
          'exercise': 'した',
          'study': 'した',
          'custom_0': 'はい',
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
      {
        'diary': '六時間の睡眠。午前は統計学と線形代数の講義で埋まっていた。昼、依頼人は学内の図書館へ向かう。初めて自習室を予約し、その一室にこもったという。静寂が思考を運び、停滞していたレポートは一気に最後まで書き上がった。本人は「集中できた」と手応えを語っている。夕食を済ませると糸が切れたように眠りに落ちたことが記録されている。短い夜だったが、机の上の達成は確かだ。',
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
      {
        'diary': '午前のプログラミング演習を終え、依頼人は研究室にこもった。午後いっぱいを費やした相手は、pandasのgroupbyに潜む一つのバグ。ドキュメントを丹念に読み返すうち、原因はようやく姿を現したという。長く追い続けた糸口がほどけた瞬間、本人は「すっきりした」と短く息を吐いた。夜はジムでランニングとストレッチ。自炊の鶏むね肉で締めた一日は、頭も体も使い切ったことが確認された。睡眠は七時間。',
        'answers': {
          'sleep': '7時間',
          'food': '鶏むね肉の照り焼き（自炊）',
          'exercise': 'した',
          'study': 'した',
          'custom_0': 'はい',
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
      {
        'diary': '睡眠は五時間と短い。午前は機械学習入門のオンライン講義に充て、午後は近所を三十分歩いてから昼寝で体を整えたという。夜、依頼人は友人に誘われ居酒屋の席に着いた。長らく苦手としてきたレバーが運ばれてくる。意を決して口に運ぶと、不思議と箸が止まらず、ついには完食。本人も「自分でも驚いた」と面白がっている。唐揚げと枝豆を囲んだ賑やかな夜だったことが記録されている。',
        'answers': {
          'sleep': '5時間',
          'food': '居酒屋',
          'exercise': 'した',
          'study': 'した',
          'custom_0': 'はい',
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
      {
        'diary': '八時間の睡眠が、この日の冴えを支えていたのかもしれない。午前は英語とデータ構造の講義。その流れのまま、午後の図書館で依頼人は試験勉強に没頭した。ふと、習ったばかりのヒープを何も見ずに一から書き起こしてみたという。手は驚くほど滑らかに動き、コードは淀みなく組み上がった。「自信がついた」と本人は手応えを口にしている。帰宅後は入浴と読書で静かに一日を閉じたことが確認された。',
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
      {
        'diary': '六時間の睡眠で迎えた朝は、確率論の講義と小テストから始まった。午後四時、依頼人はカフェの制服に袖を通す。閉店までの五時間、いつもは言葉少なに皿を運ぶだけの本人が、この日は常連客へ自ら声をかけたという。新メニューの感想を尋ねると、相手は思いのほか饒舌に語ってくれた。「聞いてよかった」と本人は嬉しげだ。まかないのカレーで腹を満たし、帰宅後はシャワーを浴びて床に就いたことが記録されている。',
        'answers': {
          'sleep': '6時間',
          'food': 'アルバイト先でまかない（カレー）',
          'exercise': 'していない',
          'study': 'した',
          'custom_0': 'はい',
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
      {
        'diary': '九時間。たっぷりの睡眠から始まった休日だった。午前はYoutubeを横目にストレッチで体をほぐし、ホットケーキで遅い朝食を取ったという。午後からはハッカソンの開発に没頭。FlutterにGemini APIをつなぎ込む作業が、夜になってついに実を結んだ。画面の向こうでAIが初めて返答を寄こした瞬間、依頼人は「感動した」と声を弾ませている。デリバリーのピザで祝杯をあげ、レビューの準備まで手をつけたことが確認された。',
        'answers': {
          'sleep': '9時間',
          'food': 'デリバリーのピザ',
          'exercise': 'していない',
          'study': 'した',
          'custom_0': 'はい',
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
      {
        'diary': '夜明け前、まだ街が眠るうちに依頼人は布団を抜け出した。七時間の睡眠で目覚めは軽い。向かった先は近所の公園。これまで縁のなかった早朝のランニングに、思い切って足を踏み出したという。澄んだ空気と人気のない並木道は、想像していたよりずっと心地よかったらしい。「面白かった」と本人は息を弾ませている。午後はアルゴリズムの講義に出席し、鮭の塩焼きで夕食を済ませると、いつもより早く床に就いたことが記録されている。',
        'answers': {
          'sleep': '7時間',
          'food': '鮭の塩焼き（自炊）',
          'exercise': 'した',
          'study': 'していない',
          'custom_0': 'はい',
          'custom_1': '思い切って早朝ランニングを始めてみた',
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
        'diary': '六時間の睡眠。午前から依頼人はスライドの最終確認に余念がなかった。迎えた午後、研究室の輪講。初めて発表者の側に立った本人は、用意してきた論文の要点を一つずつ言葉にしていったという。質疑にも詰まることなく応じ、終えたときには大役を果たした実感が残った。「やりきった」と本人は晴れやかだ。夜は友人との通話でささやかな打ち上げ。張り詰めた一日を、笑い声で締めくくったことが確認された。',
        'answers': {
          'sleep': '6時間',
          'food': '学食の定食',
          'exercise': 'していない',
          'study': 'した',
          'custom_0': 'はい',
          'custom_1': '研究室の輪講で初めて発表を担当した',
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
        'diary': '七時間の睡眠で迎えた一日は、微分積分の講義から動き出した。午後は課題と読書に費やし、帰路、依頼人はふと路地裏の古本屋に立ち寄ったという。棚を端から目で追っていた指が、一冊で止まる。長く探し続けていた絶版の数学書が、そこに静かに収まっていた。「まさかここで」と本人は声を漏らしている。思わぬ巡り合わせを抱えて家路についた夜だった。よく歩き、よく学んだ一日だったことが記録されている。',
        'answers': {
          'sleep': '7時間',
          'food': 'カフェのサンドイッチ',
          'exercise': 'した',
          'study': 'した',
          'custom_0': 'はい',
          'custom_1': '長く探していた絶版の数学書を古本屋で手に入れた',
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
        'diary': '終日の雨。八時間眠った依頼人は、雨音を聞きながらの二度寝という贅沢から一日を始めたという。午後は録りためた番組をゆっくりと消化。これといった予定のない、静かな休日だった。夜になり、本人はかねて気になっていたスパイスからのカレー作りに腰を据える。慣れない計量と火加減に手こずりながらも、台所には次第に本格的な香りが立ち込めていった。「面白かった」と本人。雨の一日を、湯気の向こうで締めくくったことが確認された。',
        'answers': {
          'sleep': '8時間',
          'food': 'スパイスから作ったカレー',
          'exercise': 'していない',
          'study': 'していない',
          'custom_0': 'いいえ',
          'custom_1': 'スパイスを調合して一からカレーを作ってみた',
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
        'diary': '六時間の睡眠で始まった一日は、線形代数の講義と図書館での予習で過ぎていった。夜、依頼人はアルバイト先のカフェに立つ。閉店後、店長から初めてレジ締めを任されたという。売上を数え、帳簿と突き合わせる一連の作業を、同僚に教わりながら最後までやり遂げた。数字がぴたりと合ったとき、信頼されている手応えが胸に残ったらしい。「任せてもらえて嬉しかった」と本人。まかないで腹を満たし、夜道を帰っていったことが記録されている。',
        'answers': {
          'sleep': '6時間',
          'food': 'アルバイト先のまかない',
          'exercise': 'していない',
          'study': 'した',
          'custom_0': 'はい',
          'custom_1': 'バイトで初めてレジ締めを任された',
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
        'diary': '五時間の睡眠で迎えた朝、確率統計の講義までは穏やかに進んでいた。事は午後に起きる。作りかけていたプレゼン資料が、保存の手違いで消えていたという。依頼人は気を取り直し、記憶を頼りに一から組み直す作業へ取りかかった。手は止めず、夕方までに資料はかつての形を取り戻していった。夜には同じことを繰り返さぬよう、クラウドへの自動バックアップを設定したと本人は語っている。教訓を一つ手にした一日だったことが記録されている。',
        'answers': {
          'sleep': '5時間',
          'food': '学食のカレー',
          'exercise': 'していない',
          'study': 'した',
          'custom_0': 'いいえ',
          'custom_1': 'クラウドへの自動バックアップを設定した',
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
        'diary': '九時間眠ってもなお、体はまだ本調子ではなかったらしい。喉に違和感を覚えた依頼人は、この日の予定をすべて切り上げ、休養に充てると決めたという。午前はおかゆで胃を温め、午後は録りためていた映画をゆっくりと観て過ごした。動き回らず、ただ体の声に耳を澄ませる一日。夜は早々に床へ入っている。立ち止まることもまた、明日へ向けた支度なのだろう。無理をしなかった一日として記録されている。',
        'answers': {
          'sleep': '9時間',
          'food': 'おかゆ',
          'exercise': 'していない',
          'study': 'していない',
          'custom_0': 'いいえ',
          'custom_1': '体調を優先して一日きちんと休むと決めた',
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
}
