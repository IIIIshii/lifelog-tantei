import 'package:cloud_firestore/cloud_firestore.dart';

// 質問の入力タイプ
enum QuestionType {
  text, // 自由テキスト
  number, // 数値入力（睡眠時間など）
  singleChoice; // 選択肢から1つ選ぶ

  String get value {
    switch (this) {
      case QuestionType.text:
        return 'text';
      case QuestionType.number:
        return 'number';
      case QuestionType.singleChoice:
        return 'single_choice';
    }
  }

  static QuestionType fromValue(String? v) {
    switch (v) {
      case 'text':
        return QuestionType.text;
      case 'number':
        return QuestionType.number;
      case 'single_choice':
        return QuestionType.singleChoice;
      default:
        return QuestionType.text;
    }
  }
}

// users/{uid}/customQuestions/{questionId} のモデル
// ユーザーが自由に追加する質問。順序・有効化・論理削除をサポートする
class CustomQuestion {
  final String id;
  final String text;
  final QuestionType type;
  final List<String>? choices; // type=singleChoice のとき必須
  final String? unit; // type=number のとき "時間", "kg" など
  final bool enabled; // 一時無効化用（archivedAt とは別）
  final double order; // 並び順。double で中間値挿入を可能にする
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? archivedAt; // 論理削除フラグ（過去日記からの参照を壊さない）

  const CustomQuestion({
    required this.id,
    required this.text,
    this.type = QuestionType.text,
    this.choices,
    this.unit,
    this.enabled = true,
    this.order = 0,
    this.createdAt,
    this.updatedAt,
    this.archivedAt,
  });

  // 新規記録に使える状態か（archived でなく かつ enabled）
  bool get isActive => archivedAt == null && enabled;

  factory CustomQuestion.fromMap(String id, Map<String, dynamic> map) {
    final rawChoices = map['choices'];
    return CustomQuestion(
      id: id,
      text: map['text'] as String? ?? '',
      type: QuestionType.fromValue(map['type'] as String?),
      choices: rawChoices is List ? rawChoices.cast<String>() : null,
      unit: map['unit'] as String?,
      enabled: map['enabled'] as bool? ?? true,
      order: (map['order'] as num?)?.toDouble() ?? 0.0,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
      archivedAt: (map['archivedAt'] as Timestamp?)?.toDate(),
    );
  }

  // Firestore書き込み用マップ
  // createdAt / updatedAt / archivedAt は FirestoreService が
  // FieldValue.serverTimestamp() / null で別途付与する
  Map<String, dynamic> toMap() {
    return {
      'text': text,
      'type': type.value,
      'choices': choices,
      'unit': unit,
      'enabled': enabled,
      'order': order,
    };
  }

  CustomQuestion copyWith({
    String? text,
    QuestionType? type,
    List<String>? choices,
    String? unit,
    bool? enabled,
    double? order,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? archivedAt,
  }) {
    return CustomQuestion(
      id: id,
      text: text ?? this.text,
      type: type ?? this.type,
      choices: choices ?? this.choices,
      unit: unit ?? this.unit,
      enabled: enabled ?? this.enabled,
      order: order ?? this.order,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      archivedAt: archivedAt ?? this.archivedAt,
    );
  }
}
