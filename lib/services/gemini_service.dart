import 'package:google_generative_ai/google_generative_ai.dart';
import '../prompts/diary_prompts.dart';

// Gemini APIとのやり取りを担当するサービスクラス
// プロンプト文字列はDiaryPromptsで管理し、このクラスはAPIの呼び出しのみを担う
class GeminiService {
  final GenerativeModel _model;

  // APIキーを受け取りGeminiモデルを初期化する
  GeminiService(String apiKey)
      : _model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: apiKey);

  // ── 深堀り質問生成 ─────────────────────────────────────────
  // 会話履歴を渡して探偵スタイルの深堀り質問を生成する。
  // AIが「DONE」を返した場合（情報収集完了と判断）はnullを返す。
  // 呼び出し側はnullを受け取ったら次のフェーズへ遷移すること。
  Future<String?> generateFollowUp(List<Map<String, String>> messages) async {
    final history = _buildHistory(messages);
    final response = await _model.generateContent([
      Content.text(DiaryPrompts.followUp(history)),
    ]);
    final text = response.text?.trim() ?? '';

    // 「DONE」はバックエンド専用の終了シグナル。ユーザーには表示しない。
    if (text.toUpperCase() == 'DONE') return null;

    return text.isEmpty ? null : text;
  }

  // ── 捜査ログ（日記）生成 ───────────────────────────────────
  // 会話履歴全体から探偵視点の三人称捜査ログを生成する
  Future<String> generateDiary(List<Map<String, String>> messages) async {
    final history = _buildHistory(messages);
    final response = await _model.generateContent([
      Content.text(DiaryPrompts.generateDiary(history)),
    ]);
    return response.text?.trim() ?? '捜査ログを生成できませんでした。';
  }

  // メッセージリストを「探偵: ...」「依頼人: ...」形式に変換する
  // 探偵風の役割名にすることでAIがキャラクターを維持しやすくなる
  String _buildHistory(List<Map<String, String>> messages) {
    return messages
        .map((m) => '${m['role'] == 'ai' ? '探偵' : '依頼人'}: ${m['text']}')
        .join('\n');
  }
}
