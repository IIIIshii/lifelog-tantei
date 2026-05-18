import 'package:cloud_firestore/cloud_firestore.dart';
import 'response_entry.dart';

// 日記の生成元
enum DiarySource {
  ai, // AI生成
  manual, // ユーザー手入力
  aiThenEdited; // AI生成後にユーザーが編集

  String get value {
    switch (this) {
      case DiarySource.ai:
        return 'ai';
      case DiarySource.manual:
        return 'manual';
      case DiarySource.aiThenEdited:
        return 'ai_then_edited';
    }
  }

  static DiarySource fromValue(String? v) {
    switch (v) {
      case 'ai':
        return DiarySource.ai;
      case 'manual':
        return DiarySource.manual;
      case 'ai_then_edited':
        return DiarySource.aiThenEdited;
      default:
        return DiarySource.ai;
    }
  }
}

// users/{uid}/days/{YYYY-MM-DD} のモデル
// 1日分の日記テキスト・質問回答・数値メトリクスを保持する
class DayEntry {
  final String date; // ドキュメントID（YYYY-MM-DD）
  final String? diary; // AI生成または手入力の日記テキスト
  final DiarySource? diarySource;
  final List<ResponseEntry> responses;
  // 数値質問だけ抽出した冗長コピー。analytics の O(1) アクセス用
  // 保存時に FirestoreService が responses から自動生成する
  final Map<String, double> metrics;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const DayEntry({
    required this.date,
    this.diary,
    this.diarySource,
    this.responses = const [],
    this.metrics = const {},
    this.createdAt,
    this.updatedAt,
  });

  // 指定 questionKey に対応する回答テキストを返す（なければnull）
  // analytics_page などで頻繁に使う lookup を簡潔にするためのヘルパー
  String? answerTextFor(String questionKey) {
    for (final r in responses) {
      if (r.questionKey == questionKey) return r.answerText;
    }
    return null;
  }

  factory DayEntry.fromMap(String date, Map<String, dynamic> map) {
    final rawResponses = map['responses'];
    final responses = rawResponses is List
        ? rawResponses
            .whereType<Map>()
            .map((m) => ResponseEntry.fromMap(m.cast<String, dynamic>()))
            .toList()
        : <ResponseEntry>[];

    final rawMetrics = map['metrics'];
    final metrics = <String, double>{};
    if (rawMetrics is Map) {
      rawMetrics.forEach((key, value) {
        if (key is String && value is num) {
          metrics[key] = value.toDouble();
        }
      });
    }

    return DayEntry(
      date: date,
      diary: map['diary'] as String?,
      diarySource: map['diarySource'] != null
          ? DiarySource.fromValue(map['diarySource'] as String?)
          : null,
      responses: responses,
      metrics: metrics,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  // Firestore書き込み用マップ
  // createdAt / updatedAt は FirestoreService が serverTimestamp で別途付与する
  Map<String, dynamic> toMap() {
    return {
      'diary': diary,
      'diarySource': diarySource?.value,
      'responses': responses.map((r) => r.toMap()).toList(),
      'metrics': metrics,
    };
  }

  DayEntry copyWith({
    String? diary,
    DiarySource? diarySource,
    List<ResponseEntry>? responses,
    Map<String, double>? metrics,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DayEntry(
      date: date,
      diary: diary ?? this.diary,
      diarySource: diarySource ?? this.diarySource,
      responses: responses ?? this.responses,
      metrics: metrics ?? this.metrics,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
