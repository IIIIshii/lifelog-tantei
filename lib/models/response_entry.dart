import 'package:cloud_firestore/cloud_firestore.dart';
import 'custom_question.dart';

// 回答の出所（どこから来た質問か）
// プレフィックス命名規則（"custom_*", "event_*"）に代わる正式な分類
enum ResponseSource {
  appFixed, // 設定ベースの固定質問（sleep / food / exercise / study）
  appEvent, // 出来事の構造化質問（event_when / where / who / what / how）
  appRecall, // 思い出しアシスト（morning / afternoon / evening）
  userCustom, // ユーザー定義のカスタム質問
  aiFollowUp, // AIによる深掘り質問
  addendum; // 追記事項

  String get value {
    switch (this) {
      case ResponseSource.appFixed:
        return 'app_fixed';
      case ResponseSource.appEvent:
        return 'app_event';
      case ResponseSource.appRecall:
        return 'app_recall';
      case ResponseSource.userCustom:
        return 'user_custom';
      case ResponseSource.aiFollowUp:
        return 'ai_followup';
      case ResponseSource.addendum:
        return 'addendum';
    }
  }

  static ResponseSource fromValue(String? v) {
    switch (v) {
      case 'app_fixed':
        return ResponseSource.appFixed;
      case 'app_event':
        return ResponseSource.appEvent;
      case 'app_recall':
        return ResponseSource.appRecall;
      case 'user_custom':
        return ResponseSource.userCustom;
      case 'ai_followup':
        return ResponseSource.aiFollowUp;
      case 'addendum':
        return ResponseSource.addendum;
      default:
        return ResponseSource.appFixed;
    }
  }
}

// days/{date}.responses[] の要素モデル
// 1つの質問と回答のペアを保持する
class ResponseEntry {
  final ResponseSource source;
  final String questionKey; // "sleep" / "event_when" / "custom_<questionId>" など
  final DocumentReference? questionRef; // source=userCustom のとき customQuestions/{id} 参照
  final String questionText; // 質問文のスナップショット（編集後も元の文言を保持）
  final QuestionType questionType;
  final String? answerText;
  final double? answerNumber;
  final int? answerChoiceIndex; // 選択肢回答のインデックス（自由記述併用ケース追跡用）
  final bool includedInDiary; // AI日記生成に含めた回答か
  final int order;

  const ResponseEntry({
    required this.source,
    required this.questionKey,
    this.questionRef,
    required this.questionText,
    this.questionType = QuestionType.text,
    this.answerText,
    this.answerNumber,
    this.answerChoiceIndex,
    this.includedInDiary = true,
    required this.order,
  });

  factory ResponseEntry.fromMap(Map<String, dynamic> map) {
    return ResponseEntry(
      source: ResponseSource.fromValue(map['source'] as String?),
      questionKey: map['questionKey'] as String? ?? '',
      questionRef: map['questionRef'] as DocumentReference?,
      questionText: map['questionText'] as String? ?? '',
      questionType: QuestionType.fromValue(map['questionType'] as String?),
      answerText: map['answerText'] as String?,
      answerNumber: (map['answerNumber'] as num?)?.toDouble(),
      answerChoiceIndex: map['answerChoiceIndex'] as int?,
      includedInDiary: map['includedInDiary'] as bool? ?? true,
      order: map['order'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'source': source.value,
      'questionKey': questionKey,
      'questionRef': questionRef,
      'questionText': questionText,
      'questionType': questionType.value,
      'answerText': answerText,
      'answerNumber': answerNumber,
      'answerChoiceIndex': answerChoiceIndex,
      'includedInDiary': includedInDiary,
      'order': order,
    };
  }

  ResponseEntry copyWith({
    ResponseSource? source,
    String? questionKey,
    DocumentReference? questionRef,
    String? questionText,
    QuestionType? questionType,
    String? answerText,
    double? answerNumber,
    int? answerChoiceIndex,
    bool? includedInDiary,
    int? order,
  }) {
    return ResponseEntry(
      source: source ?? this.source,
      questionKey: questionKey ?? this.questionKey,
      questionRef: questionRef ?? this.questionRef,
      questionText: questionText ?? this.questionText,
      questionType: questionType ?? this.questionType,
      answerText: answerText ?? this.answerText,
      answerNumber: answerNumber ?? this.answerNumber,
      answerChoiceIndex: answerChoiceIndex ?? this.answerChoiceIndex,
      includedInDiary: includedInDiary ?? this.includedInDiary,
      order: order ?? this.order,
    );
  }
}
