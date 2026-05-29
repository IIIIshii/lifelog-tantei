// 探偵キャラクター（ロール）1体分の定義を表すモデル。
// Geminiへ渡す人格指示・固定質問文・ナレーション文・表示ラベルを1か所にまとめる。
// 実行時のGemini生成は行わず、ここに静的に書かれた文面をそのまま使う。
//
// questionTexts のキー（全ロール共通の語彙）:
//   出来事       : event_when / event_where / event_who / event_what / event_how
//   カスタム質問 : q_sleep / q_food / q_exercise / q_study
//   思い出し     : q_morning / q_afternoon / q_evening
//   ナレーション : intro_custom / confirm_include / intro_recall / intro_event / ask_addendum
//
// 注: choices（朝/昼/夜・睡眠時間など）と custom_i（ユーザー定義質問）は Role に持たせない。
//     前者は回答データとして保存・パースされる固定値、後者はユーザー入力そのものを使うため。
//     Role は「質問・ナレーションの文面」だけを担当する。
class Role {
  final String key; // 'hardboiled' など。UserSettings.selectedRole と一致させる
  final String label; // 設定画面に表示する名称
  final String interviewerInstruction; // Gemini の systemInstruction / followUp 用の人格指示
  final Map<String, String> questionTexts; // 質問・ナレーションキー → 文面

  // ボタン選択式の回答に対する固定リアクション文面。Gemini を呼ばずにそのまま使う。
  // キーは '<回答キー>:<選択肢>'（例 'event_how:悲しかった'）か '<回答キー>'（例 'sleep'）。
  // 前者は選択肢で意味が分岐するもの（感情・した/していない）、後者は共通の相槌で足りるもの。
  // 自由記述への反応は Gemini 生成（GeminiService.generateReaction）が担当するためここには持たない。
  final Map<String, String> reactionTexts;

  const Role({
    required this.key,
    required this.label,
    required this.interviewerInstruction,
    required this.questionTexts,
    this.reactionTexts = const {},
  });

  // 指定キーの文面を返す。未定義のキーは fallback を返す（安全側）。
  String text(String key, String fallback) => questionTexts[key] ?? fallback;

  // ボタン選択への固定リアクションを引く。'<key>:<answer>' を優先し、
  // 無ければ '<key>'、それも無ければ null（＝リアクションを出さない）。
  String? reaction(String key, String answer) =>
      reactionTexts['$key:$answer'] ?? reactionTexts[key];
}
