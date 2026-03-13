import 'package:google_generative_ai/google_generative_ai.dart';
import '../prompts/diary_prompts.dart';

class GeminiService {
  final GenerativeModel _model;

  GeminiService(String apiKey)
      : _model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: apiKey);

  Future<String> generateFirstQuestion() async {
    final response = await _model.generateContent([
      Content.text(DiaryPrompts.firstQuestion()),
    ]);
    return response.text ?? '今日はどんな一日でしたか？';
  }

  Future<String> generateFollowUp(List<Map<String, String>> messages) async {
    final history = _buildHistory(messages);
    final response = await _model.generateContent([
      Content.text(DiaryPrompts.followUp(history)),
    ]);
    return response.text ?? 'もう少し詳しく教えてください。';
  }

  Future<String> generateDiary(List<Map<String, String>> messages) async {
    final history = _buildHistory(messages);
    final response = await _model.generateContent([
      Content.text(DiaryPrompts.generateDiary(history)),
    ]);
    return response.text ?? '日記を生成できませんでした。';
  }

  String _buildHistory(List<Map<String, String>> messages) {
    return messages
        .map((m) => '${m['role'] == 'ai' ? 'AI' : 'ユーザー'}: ${m['text']}')
        .join('\n');
  }
}
