import 'package:google_generative_ai/google_generative_ai.dart';
import '../prompts/diary_prompts.dart';

// Gemini APIとのやり取りを担当するサービスクラス
class GeminiService {
  final GenerativeModel _model;

  // APIキーを受け取りGeminiモデルを初期化する
  GeminiService(String apiKey)
      : _model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: apiKey);

  // 今日の出来事についての最初の質問をGeminiに生成させる
  Future<String> generateFirstQuestion() async {
    final response = await _model.generateContent([
      Content.text(DiaryPrompts.firstQuestion()),
    ]);
    return response.text ?? '今日はどんな一日でしたか？';
  }

  // 会話履歴を渡して深堀り質問をGeminiに生成させる
  Future<String> generateFollowUp(List<Map<String, String>> messages) async {
    final history = _buildHistory(messages);
    final response = await _model.generateContent([
      Content.text(DiaryPrompts.followUp(history)),
    ]);
    return response.text ?? 'もう少し詳しく教えてください。';
  }

  // 会話履歴全体から日記テキストをGeminiに生成させる
  Future<String> generateDiary(List<Map<String, String>> messages) async {
    final history = _buildHistory(messages);
    final response = await _model.generateContent([
      Content.text(DiaryPrompts.generateDiary(history)),
    ]);
    return response.text ?? '日記を生成できませんでした。';
  }

  // 既存の日記と追記インタビューの会話を統合して日記テキストをGeminiに生成させる
  Future<String> generateDiaryWithExisting(
      String existingDiary, List<Map<String, String>> messages) async {
    final history = _buildHistory(messages);
    final response = await _model.generateContent([
      Content.text(DiaryPrompts.generateDiaryWithExisting(existingDiary, history)),
    ]);
    return response.text ?? '日記を生成できませんでした。';
  }

  // メッセージリストを「AI: ...」「ユーザー: ...」形式の文字列に変換する
  String _buildHistory(List<Map<String, String>> messages) {
    return messages
        .map((m) => '${m['role'] == 'ai' ? 'AI' : 'ユーザー'}: ${m['text']}')
        .join('\n');
  }
}
