import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/streak.dart';
import '../models/analysis_entry.dart';
import '../models/goal.dart';
import '../models/record_field.dart';
import '../models/self_analysis.dart';
import '../models/user_settings.dart';

// Firestoreへのデータ読み書きを担当するサービスクラス
//
// 構成:
// users/{uid}/
// ├ settings/preferences   担当探偵・通知（UserSettings）
// ├ settings/fields        記録の型 items[]（RecordField）
// ├ records/{YYYY-MM-DD}   日々の記録の実データ values{項目id: 値}
// ├ diaries/{YYYY-MM-DD}   日記の本文・話した出来事
// │   └ interview/{autoId} 聴取の会話
// ├ goals/{goalId}         目標（行動項目の定義を持つ。値は records に入る）
// ├ analyses/{autoId}      AI所見・今日のコメント（上書きせず積む）
// └ self-analysis/profile  自己分析
class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ──────────────────────────────────────────────────────────────
  // コレクション参照（パスはここに集約し、メソッドごとに直書きしない）
  // ──────────────────────────────────────────────────────────────
  DocumentReference<Map<String, dynamic>> _user(String uid) =>
      _db.collection('users').doc(uid);

  DocumentReference<Map<String, dynamic>> _preferences(String uid) =>
      _user(uid).collection('settings').doc('preferences');

  DocumentReference<Map<String, dynamic>> _fieldsDoc(String uid) =>
      _user(uid).collection('settings').doc('fields');

  CollectionReference<Map<String, dynamic>> _records(String uid) =>
      _user(uid).collection('records');

  CollectionReference<Map<String, dynamic>> _diaries(String uid) =>
      _user(uid).collection('diaries');

  CollectionReference<Map<String, dynamic>> _interview(
    String uid,
    String date,
  ) => _diaries(uid).doc(date).collection('interview');

  CollectionReference<Map<String, dynamic>> _goals(String uid) =>
      _user(uid).collection('goals');

  // ──────────────────────────────────────────────────────────────
  // 日付キーのドキュメントの共用操作（records / diaries のどちらにも使う）
  // ──────────────────────────────────────────────────────────────

  // 直近 days 日の日付キー範囲（今日を含む）。
  ({String from, String to}) _recentRange(int days) {
    final now = DateTime.now();
    return (
      from: dateKey(DateTime(now.year, now.month, now.day - (days - 1))),
      to: dateKey(now),
    );
  }

  // 日付キーの範囲でドキュメントを取る。toKey を省くと fromKey 以降すべて。
  //
  // orderBy を使わないのは doc ID が 'YYYY-MM-DD' で範囲クエリだけで足りるため
  // （複合インデックスも要らない）。呼び出し側は順序に依存しない作りになっている。
  Future<List<MapEntry<String, Map<String, dynamic>>>> _inRange(
    CollectionReference<Map<String, dynamic>> collection,
    String fromKey, {
    String? toKey,
  }) async {
    Query<Map<String, dynamic>> query = collection.where(
      FieldPath.documentId,
      isGreaterThanOrEqualTo: fromKey,
    );
    if (toKey != null) {
      query = query.where(FieldPath.documentId, isLessThanOrEqualTo: toKey);
    }
    final snap = await query.get();
    return snap.docs.map((doc) => MapEntry(doc.id, doc.data())).toList();
  }

  Future<List<MapEntry<String, Map<String, dynamic>>>> _all(
    CollectionReference<Map<String, dynamic>> collection,
  ) async {
    final snap = await collection.get();
    final entries = snap.docs.map((doc) => MapEntry(doc.id, doc.data())).toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    return entries;
  }

  Future<Map<String, dynamic>?> _doc(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    final doc = await ref.get();
    return doc.exists ? doc.data() : null;
  }

  // ──────────────────────────────────────────────────────────────
  // 設定（担当探偵・通知）
  // ──────────────────────────────────────────────────────────────

  // ユーザーの設定を取得する（存在しなければデフォルト値を返す）
  Future<UserSettings> getUserSettings(String uid) async {
    final data = await _doc(_preferences(uid));
    return data == null ? UserSettings.defaults() : UserSettings.fromMap(data);
  }

  // ユーザーの設定を保存する（全置換）
  Future<void> saveUserSettings(String uid, UserSettings settings) =>
      _preferences(uid).set(settings.toMap());

  // ──────────────────────────────────────────────────────────────
  // 記録の型（settings/fields）
  // ──────────────────────────────────────────────────────────────

  // 記録項目の定義を並び順どおりに返す。まだ保存したことが無ければプリセット。
  //
  // id の無い項目は捨てる。値のキーにできず、表に出しても保存先が無いため。
  Future<List<RecordField>> getFields(String uid) async {
    final data = await _doc(_fieldsDoc(uid));
    final raw = data?['items'];
    if (raw is! List) return kPresetFields;
    return [
      for (final item in raw)
        if (item is Map) RecordField.fromMap(Map<String, dynamic>.from(item)),
    ].where((field) => field.id.isNotEmpty).toList(growable: false);
  }

  // 記録項目の定義を丸ごと保存する（並び順もこの順で残る）。
  Future<void> saveFields(String uid, List<RecordField> fields) =>
      _fieldsDoc(uid).set({'items': fields.map((f) => f.toMap()).toList()});

  // 記録項目を1件足す。同じ名前の項目が既にあれば何もしない。
  //
  // トランザクションで読み直してから書くのは、相談室と設定画面の両方が
  // この一覧を書くため。画面が握っている古い一覧で上書きすると、
  // その間にもう一方で足した項目が消える。
  Future<void> addField(String uid, RecordField field) async {
    final ref = _fieldsDoc(uid);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final raw = snap.data()?['items'];
      final current = raw is List
          ? [
              for (final item in raw)
                if (item is Map)
                  RecordField.fromMap(Map<String, dynamic>.from(item)),
            ]
          : [...kPresetFields];
      if (current.any((f) => f.label == field.label)) return;
      tx.set(ref, {
        'items': [...current, field].map((f) => f.toMap()).toList(),
      });
    });
  }

  // ──────────────────────────────────────────────────────────────
  // 日々の記録（records/{YYYY-MM-DD}）
  // ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> getRecord(String uid, String date) =>
      _doc(_records(uid).doc(date));

  // 項目の値をまとめて書く。値が null の項目は消す（未記入に戻す）。
  //
  // merge で入れ子の values だけを書き換えるので、他の項目の値は残る。
  // 表の1項目ずつ保存するため、全体を読み直して書き戻す必要は無い。
  Future<void> saveRecordValues(
    String uid,
    String date,
    Map<String, Object?> changes,
  ) async {
    if (changes.isEmpty) return;
    await _records(uid).doc(date).set({
      'values': {
        for (final entry in changes.entries)
          entry.key: entry.value ?? FieldValue.delete(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // 直近 days 日分の記録（今日を含む）
  Future<List<MapEntry<String, Map<String, dynamic>>>> getRecentRecords(
    String uid,
    int days,
  ) {
    final range = _recentRange(days);
    return _inRange(_records(uid), range.from, toKey: range.to);
  }

  // fromKey 以降すべての記録（目標の記録一覧が着手日から辿るとき用）。
  // 上限を付けないのは、未来日付の記録が作られないため。
  Future<List<MapEntry<String, Map<String, dynamic>>>> getRecordsSince(
    String uid,
    String fromKey,
  ) => _inRange(_records(uid), fromKey);

  // 全記録を日付の降順で（CSVエクスポート用）
  Future<List<MapEntry<String, Map<String, dynamic>>>> getAllRecords(
    String uid,
  ) => _all(_records(uid));

  // ──────────────────────────────────────────────────────────────
  // 日記（diaries/{YYYY-MM-DD}）
  // ──────────────────────────────────────────────────────────────

  // その日の日記ドキュメント（text / topics / role / mode）。無ければ null。
  Future<Map<String, dynamic>?> getDiary(String uid, String date) =>
      _doc(_diaries(uid).doc(date));

  // その日の日記の本文。無い・空なら null。
  Future<String?> getDiaryText(String uid, String date) async {
    final text = ((await getDiary(uid, date))?['text'] as String?)?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  // 日記を保存する。渡したものだけを書き換える（merge）。
  //
  // topics はこの日に話した出来事の見出し。role は書いたときの担当探偵、
  // mode は作り方（'interview' = 聴取から生成 / 'manual' = 手で書いた）。
  // 手で直したときに topics や role を消さないよう、null は「触らない」の意味にしている。
  Future<void> saveDiary(
    String uid,
    String date, {
    required String text,
    List<String>? topics,
    String? role,
    String? mode,
  }) => _diaries(uid).doc(date).set({
    'text': text,
    'topics': ?topics,
    'role': ?role,
    'mode': ?mode,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  Future<List<MapEntry<String, Map<String, dynamic>>>> getRecentDiaries(
    String uid,
    int days,
  ) {
    final range = _recentRange(days);
    return _inRange(_diaries(uid), range.from, toKey: range.to);
  }

  // 全日記を日付の降順で（CSVエクスポート用）
  Future<List<MapEntry<String, Map<String, dynamic>>>> getAllDiaries(
    String uid,
  ) => _all(_diaries(uid));

  // 日付 → 本文のストリーム（事件簿アーカイブ用）。本文の無い日は含めない。
  Stream<Map<String, String>> diaryTextsStream(String uid) {
    return _diaries(uid).snapshots().map(
      (snapshot) => {
        for (final doc in snapshot.docs)
          if (((doc.data()['text'] as String?) ?? '').trim().isNotEmpty)
            doc.id: doc.data()['text'] as String,
      },
    );
  }

  // ──────────────────────────────────────────────────────────────
  // 聴取の会話（diaries/{date}/interview）
  // ──────────────────────────────────────────────────────────────

  // 既にある発言の数。同じ日に聴取をやり直しても order が衝突しないよう、
  // 新しい発言はこの続きから番号を振る。
  Future<int> getInterviewCount(String uid, String date) async {
    final snap = await _interview(uid, date).count().get();
    return snap.count ?? 0;
  }

  // 発言を1件残す。topic はその発言がどの出来事の話か（出来事の選択中などは null）。
  Future<void> saveInterviewMessage(
    String uid,
    String date, {
    required String role,
    required String text,
    required int order,
    String? topic,
  }) => _interview(uid, date).add({
    'role': role,
    'text': text,
    'order': order,
    'topic': ?topic,
    'timestamp': FieldValue.serverTimestamp(),
  });

  // ──────────────────────────────────────────────────────────────
  // AI所見・今日のコメント（analyses/{autoId} に積む）
  // ──────────────────────────────────────────────────────────────

  // 所見を1件足す。上書きはしない（過去の所見を読み返せるようにするため）。
  Future<void> addAnalysis(String uid, AnalysisEntry entry) =>
      _user(uid).collection('analyses').add({
        ...entry.toMap(),
        'generatedAt': FieldValue.serverTimestamp(),
      });

  // 所見を新しい順に返す。種類（所見／今日のコメント）での絞り込みは呼び出し側で行う。
  //
  // where(kind) と orderBy(generatedAt) を組み合わせないのは、複合インデックスを
  // コンソールで作る手間を避けるため。1人ぶんの所見なら、新しい順に取って
  // 手元で振り分けても量は知れている。種類の読めない古いドキュメントは捨てる。
  Future<List<AnalysisEntry>> getAnalyses(String uid, {int limit = 50}) async {
    final snap = await _user(uid)
        .collection('analyses')
        .orderBy('generatedAt', descending: true)
        .limit(limit)
        .get();
    return [
      for (final doc in snap.docs)
        ?AnalysisEntry.fromMap(
          doc.id,
          doc.data(),
          generatedAt: (doc.data()['generatedAt'] as Timestamp?)?.toDate(),
        ),
    ];
  }

  // ──────────────────────────────────────────────────────────────
  // 自己分析
  // ──────────────────────────────────────────────────────────────

  // ユーザーの自己分析（MBTI等）を取得する（存在しなければデフォルト＝未登録を返す）
  // 保存先を settings/preferences と分けているのは、記録の設定ではなく依頼人本人の属性であり、
  // 今後 MBTI 以外の項目を足していく前提のため。
  Future<SelfAnalysis> getSelfAnalysis(String uid) async {
    final data = await _doc(_user(uid).collection('self-analysis').doc('profile'));
    return data == null ? SelfAnalysis.defaults() : SelfAnalysis.fromMap(data);
  }

  // ユーザーの自己分析をFirestoreに保存する
  Future<void> saveSelfAnalysis(String uid, SelfAnalysis selfAnalysis) => _user(
    uid,
  ).collection('self-analysis').doc('profile').set(selfAnalysis.toMap());

  // ──────────────────────────────────────────────────────────────
  // 目標
  // ──────────────────────────────────────────────────────────────

  // 追跡中の目標を新しい順で返す。1件も無ければ空リスト。
  //
  // 追跡を終えたものは読まない（status で分かるが、ここでは捨てる）。
  // goal-archive の移行も行わない ―― 解決済みを画面に出す相談室ハブだけが
  // getAllGoals を呼び、そこで一度きりの引き上げを済ませる。
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
  // ドキュメントが残っていれば、ここで goals/{goalId} へ移して current を消す
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
  // 読めたものは書き戻しの成否にかかわらず返す。書き込みと削除を WriteBatch で
  // まとめるのは、片方だけ通ると同じ事件が解決済みの棚に二重で出るため。
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
  Future<void> saveGoal(String uid, Goal goal) async {
    if (goal.id.isEmpty) {
      throw ArgumentError.value(goal.id, 'goal.id', '目標のIDが空です');
    }
    await _goals(uid).doc(goal.id).set(goal.toMap());
  }

  // 目標の追跡を終える。ドキュメントは消さず status と closedAt を書き換えるだけ。
  //
  // 消さないのは、行動項目の定義（ラベル・単位）が目標の側にしか無いため。
  // 消すと records に残った 'goal_<id>' の値が何の記録だったのか読めなくなる。
  // closedAt は 'YYYY-MM-DD'（呼び出し側が dateKey で渡す）。
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
  // デモ用データ
  // ──────────────────────────────────────────────────────────────

  // デモ用のモックデータを14日分書き込む。
  // 日付は固定せず、今日を基準に「13日前〜今日」へ動的に割り当てるため、
  // 直近の表示やAI分析（直近14日参照）にも必ずデモデータが反映される。
  // あわせて記録の型（プリセット全部とカスタム項目2件）も投入し、
  // 値のキーと定義が食い違わない「設定済みの状態」を再現する。
  Future<void> seedMockData(String uid) async {
    const q1 = '${kCustomFieldPrefix}mock-q1';
    const q2 = '${kCustomFieldPrefix}mock-q2';
    await saveFields(uid, [
      for (final field in kPresetFields) field.copyWith(active: true),
      const RecordField(
        id: q1,
        label: '心が動く瞬間はあった？',
        kind: FieldKind.yesNo,
        source: FieldSource.self,
      ),
      const RecordField(
        id: q2,
        label: '初めて・新しく挑戦したこと',
        source: FieldSource.self,
      ),
    ]);

    // 古い順（13日前→今日）。doc ID は投入時に動的に決める。
    final days = <_MockDay>[
      const _MockDay(
        topic: '初めて注文を全部英語でしてみた',
        diary:
            '七時間の睡眠で一日が明けた。午前を洗濯と部屋の片付けに充てた依頼人は、昼下がり、近所のカフェにいた。読書の手を止め、ふと思い立って注文をすべて英語で通したという。店員はごく自然に応じ、拍子抜けするほど呆気なく事は済んだ。本人は「面白かった」とだけ漏らしている。夜は友人とのオンラインゲーム。体も頭も程よく動かした一日だったことが確認された。',
        sleep: 7,
        mood: 'とても良い',
        exercise: true,
        study: true,
        food: 'カフェのパスタ',
        moved: true,
        challenge: 'カフェで初めてオーダーを全部英語でしてみた',
        morning: '洗濯と部屋の掃除をした',
        afternoon: '近所のカフェで本を読んだ',
        evening: '友人とオンラインゲームをした',
      ),
      const _MockDay(
        topic: '図書館の自習室でレポートを書き上げた',
        diary:
            '六時間の睡眠。午前は統計学と線形代数の講義で埋まっていた。昼、依頼人は学内の図書館へ向かう。初めて自習室を予約し、その一室にこもったという。静寂が思考を運び、停滞していたレポートは一気に最後まで書き上がった。本人は「集中できた」と手応えを語っている。夕食を済ませると糸が切れたように眠りに落ちたことが記録されている。短い夜だったが、机の上の達成は確かだ。',
        sleep: 6,
        mood: '良い',
        exercise: false,
        study: true,
        food: '学食のカレー',
        moved: true,
        challenge: '図書館の自習室を初めて予約して使った',
        morning: '授業（統計学・線形代数）',
        afternoon: '図書館で課題レポートを書いた',
        evening: '夕食後すぐ寝てしまった',
      ),
      const _MockDay(
        topic: 'groupby のバグをやっと解決した',
        diary:
            '午前のプログラミング演習を終え、依頼人は研究室にこもった。午後いっぱいを費やした相手は、pandasのgroupbyに潜む一つのバグ。ドキュメントを丹念に読み返すうち、原因はようやく姿を現したという。長く追い続けた糸口がほどけた瞬間、本人は「すっきりした」と短く息を吐いた。夜はジムでランニングとストレッチ。自炊の鶏むね肉で締めた一日は、頭も体も使い切ったことが確認された。睡眠は七時間。',
        sleep: 7,
        mood: '良い',
        exercise: true,
        study: true,
        food: '鶏むね肉の照り焼き（自炊）',
        moved: true,
        challenge: 'pandasのgroupbyを初めて使いこなせた',
        morning: '授業（プログラミング演習）',
        afternoon: '研究室でPythonのデバッグ作業',
        evening: 'ジムでランニングとストレッチ',
      ),
      const _MockDay(
        topic: '苦手なレバーを初めて完食した',
        diary:
            '睡眠は五時間と短い。午前は機械学習入門のオンライン講義に充て、午後は近所を三十分歩いてから昼寝で体を整えたという。夜、依頼人は友人に誘われ居酒屋の席に着いた。長らく苦手としてきたレバーが運ばれてくる。意を決して口に運ぶと、不思議と箸が止まらず、ついには完食。本人も「自分でも驚いた」と面白がっている。唐揚げと枝豆を囲んだ賑やかな夜だったことが記録されている。',
        sleep: 5,
        mood: 'とても良い',
        exercise: true,
        study: true,
        food: '居酒屋',
        moved: true,
        challenge: '居酒屋で苦手なレバーを初めて完食できた',
        morning: 'オンライン講義（機械学習入門）の視聴',
        afternoon: '近所を30分散歩してから昼寝',
        evening: '友人と居酒屋に行った',
      ),
      const _MockDay(
        topic: 'ヒープを手書きで実装できた',
        diary:
            '八時間の睡眠が、この日の冴えを支えていたのかもしれない。午前は英語とデータ構造の講義。その流れのまま、午後の図書館で依頼人は試験勉強に没頭した。ふと、習ったばかりのヒープを何も見ずに一から書き起こしてみたという。手は驚くほど滑らかに動き、コードは淀みなく組み上がった。「自信がついた」と本人は手応えを口にしている。帰宅後は入浴と読書で静かに一日を閉じたことが確認された。',
        sleep: 8,
        mood: '良い',
        exercise: false,
        study: true,
        food: '日替わり定食',
        moved: true,
        challenge: 'ヒープの実装を手書きで1から書いてみた',
        morning: '授業（英語・データ構造）',
        afternoon: '図書館で試験勉強',
        evening: '帰宅後すぐ入浴・読書',
      ),
      const _MockDay(
        topic: '常連さんに新メニューの感想を聞いた',
        diary:
            '六時間の睡眠で迎えた朝は、確率論の講義と小テストから始まった。午後四時、依頼人はカフェの制服に袖を通す。閉店までの五時間、いつもは言葉少なに皿を運ぶだけの本人が、この日は常連客へ自ら声をかけたという。新メニューの感想を尋ねると、相手は思いのほか饒舌に語ってくれた。「聞いてよかった」と本人は嬉しげだ。まかないのカレーで腹を満たし、帰宅後はシャワーを浴びて床に就いたことが記録されている。',
        sleep: 6,
        mood: '良い',
        exercise: false,
        study: true,
        food: 'アルバイト先でまかない（カレー）',
        moved: true,
        challenge: 'バイト中に常連さんから新メニューの感想を自分から聞いてみた',
        morning: '授業（確率論）・小テスト',
        afternoon: 'カフェでアルバイト（16〜21時）',
        evening: '帰宅後シャワーを浴びて就寝',
      ),
      const _MockDay(
        topic: 'Gemini API のアプリが初めて動いた',
        diary:
            '九時間。たっぷりの睡眠から始まった休日だった。午前はYoutubeを横目にストレッチで体をほぐし、ホットケーキで遅い朝食を取ったという。午後からはハッカソンの開発に没頭。FlutterにGemini APIをつなぎ込む作業が、夜になってついに実を結んだ。画面の向こうでAIが初めて返答を寄こした瞬間、依頼人は「感動した」と声を弾ませている。デリバリーのピザで祝杯をあげ、レビューの準備まで手をつけたことが確認された。',
        sleep: 9,
        mood: '良い',
        exercise: false,
        study: true,
        food: 'デリバリーのピザ',
        moved: true,
        challenge: 'Gemini APIを使ったアプリを初めて動かせた',
        morning: 'ゆっくり起床・Youtubeを見ながらストレッチ',
        afternoon: 'ハッカソンの作業（Flutterアプリ開発）',
        evening: '作業の続き・レビュー準備',
      ),
      const _MockDay(
        topic: '早起きして公園を走った',
        diary:
            '夜明け前、まだ街が眠るうちに依頼人は布団を抜け出した。七時間の睡眠で目覚めは軽い。向かった先は近所の公園。これまで縁のなかった早朝のランニングに、思い切って足を踏み出したという。澄んだ空気と人気のない並木道は、想像していたよりずっと心地よかったらしい。「面白かった」と本人は息を弾ませている。午後はアルゴリズムの講義に出席し、鮭の塩焼きで夕食を済ませると、いつもより早く床に就いたことが記録されている。',
        sleep: 7,
        mood: 'とても良い',
        exercise: true,
        study: false,
        food: '鮭の塩焼き（自炊）',
        moved: true,
        challenge: '思い切って早朝ランニングを始めてみた',
        morning: '早起きして近所の公園を走った',
        afternoon: '授業（アルゴリズム）',
        evening: '早めに就寝',
      ),
      const _MockDay(
        topic: '輪講で初めて発表した',
        diary:
            '六時間の睡眠。午前から依頼人はスライドの最終確認に余念がなかった。迎えた午後、研究室の輪講。初めて発表者の側に立った本人は、用意してきた論文の要点を一つずつ言葉にしていったという。質疑にも詰まることなく応じ、終えたときには大役を果たした実感が残った。「やりきった」と本人は晴れやかだ。夜は友人との通話でささやかな打ち上げ。張り詰めた一日を、笑い声で締めくくったことが確認された。',
        sleep: 6,
        mood: '良い',
        exercise: false,
        study: true,
        food: '学食の定食',
        moved: true,
        challenge: '研究室の輪講で初めて発表を担当した',
        morning: '発表スライドの最終確認',
        afternoon: '研究室の輪講で初めて発表した',
        evening: '友人と通話で打ち上げ',
      ),
      const _MockDay(
        topic: '絶版の数学書を古本屋で見つけた',
        diary:
            '七時間の睡眠で迎えた一日は、微分積分の講義から動き出した。午後は課題と読書に費やし、帰路、依頼人はふと路地裏の古本屋に立ち寄ったという。棚を端から目で追っていた指が、一冊で止まる。長く探し続けていた絶版の数学書が、そこに静かに収まっていた。「まさかここで」と本人は声を漏らしている。思わぬ巡り合わせを抱えて家路についた夜だった。よく歩き、よく学んだ一日だったことが記録されている。',
        sleep: 7,
        mood: '良い',
        exercise: true,
        study: true,
        food: 'カフェのサンドイッチ',
        moved: true,
        challenge: '長く探していた絶版の数学書を古本屋で手に入れた',
        morning: '授業（微分積分）',
        afternoon: '課題と読書',
        evening: '帰り道に古本屋へ立ち寄った',
      ),
      const _MockDay(
        topic: 'スパイスからカレーを作った',
        diary:
            '終日の雨。八時間眠った依頼人は、雨音を聞きながらの二度寝という贅沢から一日を始めたという。午後は録りためた番組をゆっくりと消化。これといった予定のない、静かな休日だった。夜になり、本人はかねて気になっていたスパイスからのカレー作りに腰を据える。慣れない計量と火加減に手こずりながらも、台所には次第に本格的な香りが立ち込めていった。「面白かった」と本人。雨の一日を、湯気の向こうで締めくくったことが確認された。',
        sleep: 8,
        mood: 'とても良い',
        exercise: false,
        study: false,
        food: 'スパイスから作ったカレー',
        moved: false,
        challenge: 'スパイスを調合して一からカレーを作ってみた',
        morning: '雨音を聞きながら二度寝',
        afternoon: '録画した番組をゆっくり消化',
        evening: 'スパイスからカレー作りに挑戦',
      ),
      const _MockDay(
        topic: '初めてレジ締めを任された',
        diary:
            '六時間の睡眠で始まった一日は、線形代数の講義と図書館での予習で過ぎていった。夜、依頼人はアルバイト先のカフェに立つ。閉店後、店長から初めてレジ締めを任されたという。売上を数え、帳簿と突き合わせる一連の作業を、同僚に教わりながら最後までやり遂げた。数字がぴたりと合ったとき、信頼されている手応えが胸に残ったらしい。「任せてもらえて嬉しかった」と本人。まかないで腹を満たし、夜道を帰っていったことが記録されている。',
        sleep: 6,
        mood: '良い',
        exercise: false,
        study: true,
        food: 'アルバイト先のまかない',
        moved: true,
        challenge: 'バイトで初めてレジ締めを任された',
        morning: '授業（線形代数）',
        afternoon: '図書館で予習',
        evening: 'カフェのアルバイトで初めてレジ締めをした',
      ),
      const _MockDay(
        topic: 'プレゼン資料を一から作り直した',
        diary:
            '五時間の睡眠で迎えた朝、確率統計の講義までは穏やかに進んでいた。事は午後に起きる。作りかけていたプレゼン資料が、保存の手違いで消えていたという。依頼人は気を取り直し、記憶を頼りに一から組み直す作業へ取りかかった。手は止めず、夕方までに資料はかつての形を取り戻していった。夜には同じことを繰り返さぬよう、クラウドへの自動バックアップを設定したと本人は語っている。教訓を一つ手にした一日だったことが記録されている。',
        sleep: 5,
        mood: 'よくない',
        exercise: false,
        study: true,
        food: '学食のカレー',
        moved: false,
        challenge: 'クラウドへの自動バックアップを設定した',
        morning: '授業（確率統計）',
        afternoon: '消えたプレゼン資料を作り直した',
        evening: 'バックアップ環境を見直した',
      ),
      const _MockDay(
        topic: '体調を優先して一日休んだ',
        diary:
            '九時間眠ってもなお、体はまだ本調子ではなかったらしい。喉に違和感を覚えた依頼人は、この日の予定をすべて切り上げ、休養に充てると決めたという。午前はおかゆで胃を温め、午後は録りためていた映画をゆっくりと観て過ごした。動き回らず、ただ体の声に耳を澄ませる一日。夜は早々に床へ入っている。立ち止まることもまた、明日へ向けた支度なのだろう。無理をしなかった一日として記録されている。',
        sleep: 9,
        mood: 'いまいち',
        exercise: false,
        study: false,
        food: 'おかゆ',
        moved: false,
        challenge: '体調を優先して一日きちんと休むと決めた',
        morning: '体調を整えるため終日休養',
        afternoon: '録画していた映画を観た',
        evening: '早めに就寝',
      ),
    ];

    // days[0] が13日前、days[last] が今日になるよう日付を割り当てる
    final today = DateTime.now();
    final batch = _db.batch();
    for (var i = 0; i < days.length; i++) {
      final day = days[i];
      final date = dateKey(
        DateTime(today.year, today.month, today.day - (days.length - 1 - i)),
      );
      batch.set(_records(uid).doc(date), {
        'values': {
          kSleepFieldId: day.sleep,
          kMoodFieldId: day.mood,
          kExerciseFieldId: day.exercise,
          kStudyFieldId: day.study,
          kFoodFieldId: day.food,
          kMorningFieldId: day.morning,
          kAfternoonFieldId: day.afternoon,
          kEveningFieldId: day.evening,
          q1: day.moved,
          q2: day.challenge,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      });
      batch.set(_diaries(uid).doc(date), {
        'text': day.diary,
        'topics': [day.topic],
        'role': 'hardboiled',
        'mode': 'interview',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
}

// デモデータ1日分。records と diaries の両方をここから組み立てる。
class _MockDay {
  final String topic;
  final String diary;
  final double sleep;
  final String mood;
  final bool exercise;
  final bool study;
  final String food;
  final bool moved; // カスタム項目「心が動く瞬間はあった？」
  final String challenge; // カスタム項目「初めて・新しく挑戦したこと」
  final String morning;
  final String afternoon;
  final String evening;

  const _MockDay({
    required this.topic,
    required this.diary,
    required this.sleep,
    required this.mood,
    required this.exercise,
    required this.study,
    required this.food,
    required this.moved,
    required this.challenge,
    required this.morning,
    required this.afternoon,
    required this.evening,
  });
}
