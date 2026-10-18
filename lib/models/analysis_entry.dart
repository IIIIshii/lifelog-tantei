// 分析室で AI が書いた所見1件。users/{uid}/analyses/{autoId} に積んでいく。
//
// 以前は analyses/latest・analyses/today を上書きしていて、新しく推理させると
// 前の所見が消えていた。積むようにしたことで、過去の所見を読み返せる。
//
// このファイルは cloud_firestore に依存させない（Timestamp → DateTime の変換は
// FirestoreService の仕事。Goal と同じ方針）。

/// 所見の種類
enum AnalysisKind {
  period, // 直近の期間をまとめた「探偵の所見」
  daily, // 今日1日への「今日のコメント」
}

String analysisKindTo(AnalysisKind kind) =>
    kind == AnalysisKind.daily ? 'daily' : 'period';

// 読めない値・記録の無いものは null（どちらの棚にも出さない）。
// 上書き方式だった頃の analyses/latest・today には種類が無いので、ここで外れる。
AnalysisKind? analysisKindFrom(String? raw) => switch (raw) {
  'period' => AnalysisKind.period,
  'daily' => AnalysisKind.daily,
  _ => null,
};

/// 画面に出す種類の名前
String analysisKindLabel(AnalysisKind kind, {int? periodDays}) =>
    switch (kind) {
      AnalysisKind.period =>
        periodDays == null ? '探偵の所見' : '探偵の所見（直近$periodDays日）',
      AnalysisKind.daily => '今日のコメント',
    };

class AnalysisEntry {
  final String id;
  final AnalysisKind kind;
  final String text;

  /// 書いた日（'YYYY-MM-DD'）。今日のコメントは、この日についてのコメント。
  final String date;

  /// 所見がまとめた期間の日数。今日のコメントは null。
  final int? periodDays;

  /// 書いた時刻。書き込み直後でサーバー時刻が確定していないときは null。
  final DateTime? generatedAt;

  const AnalysisEntry({
    required this.id,
    required this.kind,
    required this.text,
    required this.date,
    this.periodDays,
    this.generatedAt,
  });

  /// 保存されたドキュメントから読む。種類か本文が読めないものは null。
  static AnalysisEntry? fromMap(
    String id,
    Map<String, dynamic> map, {
    DateTime? generatedAt,
  }) {
    final kind = analysisKindFrom(map['kind'] as String?);
    final text = (map['text'] as String?)?.trim() ?? '';
    if (kind == null || text.isEmpty) return null;
    final period = map['periodDays'];
    return AnalysisEntry(
      id: id,
      kind: kind,
      text: text,
      date: map['date'] as String? ?? '',
      periodDays: period is int ? period : null,
      generatedAt: generatedAt,
    );
  }

  /// 保存する形（generatedAt はサーバー時刻で入れるので呼び出し側が足す）
  Map<String, dynamic> toMap() => {
    'kind': analysisKindTo(kind),
    'text': text,
    'date': date,
    'periodDays': ?periodDays,
  };
}

/// 新しい順に並んだ所見から、指定の種類で一番新しいものを返す。
/// onDate を渡すと、その日に書いたものに限る（今日のコメントは日が変わったら出さない）。
AnalysisEntry? latestAnalysis(
  Iterable<AnalysisEntry> newestFirst,
  AnalysisKind kind, {
  String? onDate,
}) {
  for (final entry in newestFirst) {
    if (entry.kind != kind) continue;
    if (onDate != null && entry.date != onDate) continue;
    return entry;
  }
  return null;
}
