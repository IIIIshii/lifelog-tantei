import 'mbti_type.dart';

// ユーザーが自分について登録した情報（自己分析）を保持するモデル。
// 保存先は users/{uid}/self-analysis/profile（UserSettings とは別コレクション）。
//
// 記録の設定（UserSettings）と分けている理由:
// こちらは「依頼人がどういう人物か」という本人の属性であり、
// 今後 MBTI 以外の項目（価値観・生活パターンなど）を足していく前提のため。
//
// shareWith* のトグルは、この情報を探偵AIのプロンプトへ渡すかどうかをユーザーが決めるためのもの。
// 既定を true にしているのは、登録したのに別途トグルを入れないと効かない状態を避けるため。
// mbti が未登録なら promptSummary() が空文字を返すので、既定ONでも何も渡らない。
class SelfAnalysis {
  final String mbti; // 'INTJ' など。未登録は空文字
  final bool shareWithInterview; // 対話AI（深掘り質問・相槌・思い出し質問）に渡すか
  final bool shareWithAnalysis; // 日記分析（所見・今日のコメント）に渡すか

  const SelfAnalysis({
    this.mbti = '',
    this.shareWithInterview = true,
    this.shareWithAnalysis = true,
  });

  // デフォルト（何も登録していない状態）を返すファクトリ
  factory SelfAnalysis.defaults() => const SelfAnalysis();

  // Firestoreのマップからインスタンスを生成するファクトリ。
  // 項目を後から増やしても既存ドキュメントが読めるよう、欠損はデフォルトで埋める。
  factory SelfAnalysis.fromMap(Map<String, dynamic> map) {
    return SelfAnalysis(
      mbti: map['mbti'] as String? ?? '',
      shareWithInterview: map['shareWithInterview'] as bool? ?? true,
      shareWithAnalysis: map['shareWithAnalysis'] as bool? ?? true,
    );
  }

  // Firestoreへ保存する際のマップへシリアライズするメソッド
  Map<String, dynamic> toMap() {
    return {
      'mbti': mbti,
      'shareWithInterview': shareWithInterview,
      'shareWithAnalysis': shareWithAnalysis,
    };
  }

  // 一部のフィールドだけ変更した新しいインスタンスを返すメソッド
  SelfAnalysis copyWith({
    String? mbti,
    bool? shareWithInterview,
    bool? shareWithAnalysis,
  }) {
    return SelfAnalysis(
      mbti: mbti ?? this.mbti,
      shareWithInterview: shareWithInterview ?? this.shareWithInterview,
      shareWithAnalysis: shareWithAnalysis ?? this.shareWithAnalysis,
    );
  }

  // AIへ渡せる中身が実際にあるか。未登録・未知のキーはどちらも false。
  bool get hasProfile => mbtiTypeFor(mbti) != null;

  // 探偵AIのプロンプトへ差し込む事実の要約を返す。
  // 登録が無ければ空文字を返し、呼び出し側でセクションごと省略できるようにする
  // （DiaryPrompts の additionalContext と同じ「空なら丸ごと省く」流儀）。
  String promptSummary() {
    final type = mbtiTypeFor(mbti);
    if (type == null) return '';
    return '- MBTI: ${type.key}（${type.label}）— ${type.description}';
  }
}
