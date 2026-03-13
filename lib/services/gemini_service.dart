import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../models/user_settings.dart';

class GeminiService {
  final GenerativeModel _model;

  GeminiService(String apiKey)
      : _model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: apiKey);

  /// 会話を踏まえたAI追加質問を1つ生成する
  Future<String> generateAIFollowUp(List<Map<String, String>> messages) async {
    final history = messages
        .map((m) => '${m['role'] == 'ai' ? 'AI' : 'ユーザー'}: ${m['text']}')
        .join('\n');
    final prompt =
        '以下は日記インタビューの会話です:\n$history\n\nユーザーの回答を踏まえて、もう少し深堀りする自然な追加質問を1つだけしてください。';
    final response = await _model.generateContent([Content.text(prompt)]);
    return response.text ?? 'もう少し詳しく教えてください。';
  }

  Future<String> generateDiary(
    List<Map<String, String>> messages, {
    String? existingDiary,
  }) async {
    final history = messages
        .map((m) => '${m['role'] == 'ai' ? 'AI' : 'ユーザー'}: ${m['text']}')
        .join('\n');

    final String prompt;
    if (existingDiary != null) {
      prompt =
          '以下の既存の日記と新たな会話内容を統合して、ユーザーの視点で100〜400字の自然な日記を生成してください。\n\n'
          '【既存の日記】\n$existingDiary\n\n'
          '【追加の会話】\n$history';
    } else {
      prompt =
          '以下の会話を元に、ユーザーの視点で100〜300字の自然な日記を生成してください。\n\n$history';
    }

    final response = await _model.generateContent([Content.text(prompt)]);
    return response.text ?? '日記を生成できませんでした。';
  }

  /// 会話から設定項目に対応する構造化データをJSONで抽出する
  Future<Map<String, dynamic>> extractStats(
      List<Map<String, String>> messages, UserSettings settings) async {
    final history = messages
        .map((m) => '${m['role'] == 'ai' ? 'AI' : 'ユーザー'}: ${m['text']}')
        .join('\n');

    final fields = <String>[];
    if (settings.recordSleep) fields.add('"sleep": 睡眠時間（数値、時間単位。不明なら null）');
    if (settings.recordExercise) fields.add('"exercise": 運動したか（true/false。不明なら null）');
    if (settings.recordFood) fields.add('"food": 食べたもののリスト（文字列配列。不明なら []）');
    if (settings.recordStudy) fields.add('"study": 勉強した内容（文字列。不明なら null）');

    if (fields.isEmpty) return {};

    final fieldDesc = fields.join('\n');
    final prompt = '''以下の会話から情報を抽出し、JSONのみを返してください。余計な説明は不要です。

フィールド:
$fieldDesc

会話:
$history

JSONのみ出力:''';

    try {
      final response = await _model.generateContent([Content.text(prompt)]);
      final raw = response.text ?? '{}';
      final cleaned = raw
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();
      return jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }
}
