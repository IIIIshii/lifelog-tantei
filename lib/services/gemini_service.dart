import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiService {
  final GenerativeModel _model;

  GeminiService(String apiKey)
      : _model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: apiKey);

  Future<String> generateFirstQuestion() async {
    final response = await _model.generateContent([
      Content.text(
          '今日の日記を書くためのインタビューをします。ユーザーに今日の出来事について、親しみやすく短い質問を1つだけしてください。'),
    ]);
    return response.text ?? '今日はどんな一日でしたか？';
  }

  Future<String> generateFollowUp(List<Map<String, String>> messages) async {
    final history = messages
        .map((m) => '${m['role'] == 'ai' ? 'AI' : 'ユーザー'}: ${m['text']}')
        .join('\n');
    final prompt =
        '以下は日記インタビューの会話です:\n$history\n\nユーザーの回答に対して、もう少し詳しく聞く自然な深堀り質問を1つだけしてください。';
    final response = await _model.generateContent([Content.text(prompt)]);
    return response.text ?? 'もう少し詳しく教えてください。';
  }

  Future<String> generateDiary(List<Map<String, String>> messages) async {
    final history = messages
        .map((m) => '${m['role'] == 'ai' ? 'AI' : 'ユーザー'}: ${m['text']}')
        .join('\n');
    final prompt =
        '以下の会話を元に、ユーザーの視点で100〜300字の自然な日記を生成してください。\n\n$history';
    final response = await _model.generateContent([Content.text(prompt)]);
    return response.text ?? '日記を生成できませんでした。';
  }
}
