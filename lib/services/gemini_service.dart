import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../prompts/ai_instructions.dart';
import '../prompts/diary_prompts.dart';
import '../roles/roles.dart';

// Gemini APIとのやり取りを担当するサービスクラス。
// インタビュー用と日記生成用でモデルを分け、それぞれに専用のシステム指示をセットする。
class GeminiService {
  // インタビュアーキャラクターとしてのシステム指示を持つモデル
  final GenerativeModel _interviewModel;
  // 日記生成ルールのシステム指示を持つモデル
  final GenerativeModel _diaryModel;
  // 過去エントリ群を読み返して所見を出すモデル
  final GenerativeModel _analysisModel;

  final String _role;

  GeminiService(String apiKey, String role)
      : _role = role,
        _interviewModel = GenerativeModel(
          model: 'gemini-2.5-flash',
          apiKey: apiKey,
          systemInstruction:
              Content.system(roleFor(role).interviewerInstruction),
          // 構造化出力: {sufficient: bool, question: string} を強制し、
          // 「DONE」文字列マッチによる脆い終了判定を廃止する
          generationConfig: GenerationConfig(
            responseMimeType: 'application/json',
            responseSchema: Schema.object(
              properties: {
                'sufficient': Schema.boolean(
                  description: '証言が十分に語られているかどうか',
                ),
                'question': Schema.string(
                  description:
                      'sufficient が false の場合の深掘り質問。true の場合は空文字でよい',
                ),
              },
              requiredProperties: ['sufficient', 'question'],
            ),
          ),
        ),
        _diaryModel = GenerativeModel(
          model: 'gemini-2.5-flash',
          apiKey: apiKey,
          systemInstruction:
              Content.system(AiInstructions.diaryWriterRole),
        ),
        _analysisModel = GenerativeModel(
          model: 'gemini-2.5-flash',
          apiKey: apiKey,
          systemInstruction:
              Content.system(AiInstructions.detectiveAnalystRole),
        );

  // 会話履歴を渡して深掘り質問をGeminiに生成させる。
  // followUpHint を隠し指示として会話履歴に付加し、UIには表示しない。
  // 戻り値の sufficient が true の場合、これ以上の深掘りは不要（呼び出し側で打ち切る）。
  // JSONパースに失敗した場合は安全側に倒し、sufficient:true として扱う。
  Future<({bool sufficient, String question})> generateFollowUp(
      List<Map<String, String>> messages) async {
    final history = _buildHistory(messages);
    final prompt =
        '${AiInstructions.followUpHint(roleFor(_role).interviewerInstruction)}\n\n以下が依頼人の証言です：\n$history';
    final response = await _interviewModel.generateContent([
      Content.text(prompt),
    ]);
    final text = response.text?.trim() ?? '';
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        final sufficient = decoded['sufficient'] == true;
        final question = (decoded['question'] as String?)?.trim() ?? '';
        if (sufficient) {
          return (sufficient: true, question: '');
        }
        return (
          sufficient: false,
          question: question.isNotEmpty ? question : 'もう少し詳しく教えてください。',
        );
      }
    } catch (_) {
      // パース失敗時はフォローアップを諦めて先に進める方が UX が良い
    }
    return (sufficient: true, question: '');
  }

  // 会話履歴から日記テキストをGeminiに生成させる。
  // additionalContext: カスタム質問・思い出しアシストの回答など、追加で含めるコンテキスト
  Future<String> generateDiary(List<Map<String, String>> messages,
      {String additionalContext = ''}) async {
    final history = _buildHistory(messages);
    final prompt = DiaryPrompts.buildDiaryPrompt(history,
        additionalContext: additionalContext);
    final response = await _diaryModel.generateContent([
      Content.text(prompt),
    ]);
    return response.text?.trim() ?? '日記を生成できませんでした。';
  }

  // 既存の日記と追記インタビューの会話を統合して日記テキストをGeminiに生成させる
  // additionalContext: カスタム質問・思い出しアシストの回答など、追加で含めるコンテキスト
  Future<String> generateDiaryWithExisting(
      String existingDiary, List<Map<String, String>> messages,
      {String additionalContext = ''}) async {
    final history = _buildHistory(messages);
    final prompt = DiaryPrompts.buildDiaryWithExistingPrompt(
        existingDiary, history,
        additionalContext: additionalContext);
    final response = await _diaryModel.generateContent([
      Content.text(prompt),
    ]);
    return response.text?.trim() ?? '日記を生成できませんでした。';
  }

  // 直近のエントリ群（日付→データ）から所見テキストをGeminiに生成させる。
  // 呼び出し側は FirestoreService.getRecentEntries の戻り値をそのまま渡せる。
  Future<String> generateAnalysis(
      List<MapEntry<String, Map<String, dynamic>>> entries) async {
    final prompt = DiaryPrompts.buildAnalysisPrompt(entries);
    final response = await _analysisModel.generateContent([
      Content.text(prompt),
    ]);
    return response.text?.trim() ?? '所見を生成できませんでした。';
  }

  // メッセージリストを「探偵: ...」「依頼人: ...」形式の文字列に変換する
  String _buildHistory(List<Map<String, String>> messages) {
    return messages
        .map((m) =>
            '${m['role'] == 'ai' ? '探偵' : '依頼人'}: ${m['text']}')
        .join('\n');
  }
}
