import 'package:google_generative_ai/google_generative_ai.dart';
import '../prompts/ai_instructions.dart';
import '../prompts/diary_prompts.dart';

// Gemini APIとのやり取りを担当するサービスクラス。
// インタビュー用と日記生成用でモデルを分け、それぞれに専用のシステム指示をセットする。
class GeminiService {
  // 前後が英数字/アンダースコア以外、または文頭/文末にある DONE を終了シグナルとして扱う。
  static final RegExp _donePattern =
      RegExp(r'(^|[^A-Z0-9_])DONE([^A-Z0-9_]|$)');

  // インタビュアーキャラクターとしてのシステム指示を持つモデル
  final GenerativeModel _interviewModel;
  // 日記生成ルールのシステム指示を持つモデル
  final GenerativeModel _diaryModel;

  GeminiService(String apiKey)
      : _interviewModel = GenerativeModel(
          model: 'gemini-2.5-flash',
          apiKey: apiKey,
          systemInstruction:
              Content.system(AiInstructions.interviewerRole),
        ),
        _diaryModel = GenerativeModel(
          model: 'gemini-2.5-flash',
          apiKey: apiKey,
          systemInstruction:
              Content.system(AiInstructions.diaryWriterRole),
        );

  // 会話履歴を渡して深掘り質問をGeminiに生成させる。
  // followUpHint を隠し指示として会話履歴に付加し、UIには表示しない。
  // Gemini が「DONE」を返した場合は null を返す（呼び出し側でスキップ処理をする）。
  Future<String?> generateFollowUp(
      List<Map<String, String>> messages) async {
    final history = _buildHistory(messages);
    final prompt = '${AiInstructions.followUpHint}\n\n以下が依頼人の証言です：\n$history';
    final response = await _interviewModel.generateContent([
      Content.text(prompt),
    ]);
    final text = response.text ?? '';
    if (isDoneResponse(text)) return null;

    final trimmedText = text.trim();
    return trimmedText.isNotEmpty ? trimmedText : 'もう少し詳しく教えてください。';
  }

  /// AI応答が対話終了を示すかどうかを判定する。
  /// 大文字小文字・前後の空白・句読点の揺れを許容し、`DONE` を終了シグナルとして検出する。
  /// `ABANDONED` のような英字単語内の部分一致は除外しつつ、日本語や記号に隣接する `DONE` は有効とする。
  static bool isDoneResponse(String text) {
    final normalized = text.trim().toUpperCase();
    return _donePattern.hasMatch(normalized);
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

  // メッセージリストを「探偵: ...」「依頼人: ...」形式の文字列に変換する
  String _buildHistory(List<Map<String, String>> messages) {
    return messages
        .map((m) =>
            '${m['role'] == 'ai' ? '探偵' : '依頼人'}: ${m['text']}')
        .join('\n');
  }
}
