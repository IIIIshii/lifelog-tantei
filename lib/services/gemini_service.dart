import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../models/goal.dart';
import '../models/record_field.dart';
import '../models/self_analysis.dart';
import '../prompts/ai_instructions.dart';
import '../prompts/diary_prompts.dart';
import '../prompts/goal_prompts.dart';
import '../roles/roles.dart';

// Gemini APIとのやり取りを担当するサービスクラス。
// 用途ごとにモデルを分け、それぞれに専用のシステム指示をセットする。
class GeminiService {
  // 聴取の深掘り質問を返すモデル（{sufficient, question} の構造化出力）
  final GenerativeModel _interviewModel;
  // 出来事への最初の質問を返すモデル。人格はインタビュアーと同じ、プレーンテキスト出力。
  final GenerativeModel _questionModel;
  // その日の記録から日記に書く出来事の候補を挙げるモデル（人格なし）
  final GenerativeModel _topicModel;
  // 日記生成ルールのシステム指示を持つモデル
  final GenerativeModel _diaryModel;
  // 過去の記録群を読み返して所見を出すモデル
  final GenerativeModel _analysisModel;
  // 相談室で目標を詰めるモデル。返答と見立てを構造化して返す。
  final GenerativeModel _consultModel;

  final String _role;

  // 自己分析（MBTI等）を systemInstruction の末尾へ差し込むためのブロック。
  // 初期化子リストでは計算ができないため、factory で組み立ててから private コンストラクタへ渡す。
  // selfAnalysis を省略した場合は何も差し込まれない。
  factory GeminiService(
    String apiKey,
    String role, {
    SelfAnalysis? selfAnalysis,
  }) {
    final summary = selfAnalysis?.promptSummary() ?? '';
    // トグルごとに渡す/渡さないを分ける。日記本文の生成（_diaryModel）には渡さない
    // ―― 日記は事実の記録であり、性格の推測を混ぜる場所ではないため。
    final interviewProfile = (selfAnalysis?.shareWithInterview ?? false)
        ? summary
        : '';
    final analysisProfile = (selfAnalysis?.shareWithAnalysis ?? false)
        ? summary
        : '';
    return GeminiService._(
      apiKey,
      role,
      AiInstructions.selfProfile(interviewProfile),
      AiInstructions.selfProfile(analysisProfile),
    );
  }

  GeminiService._(
    String apiKey,
    String role,
    String interviewProfile,
    String analysisProfile,
  ) : _role = role,
      _interviewModel = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: apiKey,
        systemInstruction: Content.system(
          '${roleFor(role).interviewerInstruction}$interviewProfile',
        ),
        // 構造化出力: {sufficient: bool, question: string} を強制し、
        // 「DONE」文字列マッチによる脆い終了判定を廃止する
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json',
          responseSchema: Schema.object(
            properties: {
              'sufficient': Schema.boolean(description: '証言が十分に語られているかどうか'),
              'question': Schema.string(
                description: 'sufficient が false の場合の深掘り質問。true の場合は空文字でよい',
              ),
            },
            requiredProperties: ['sufficient', 'question'],
          ),
        ),
      ),
      _questionModel = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: apiKey,
        systemInstruction: Content.system(
          '${roleFor(role).interviewerInstruction}$interviewProfile',
        ),
      ),
      // 候補はボタンの文言として画面に出るので、自己分析も人格も渡さない
      _topicModel = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: apiKey,
        systemInstruction: Content.system(AiInstructions.topicPicker()),
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json',
          responseSchema: Schema.object(
            properties: {
              'topics': Schema.array(
                items: Schema.string(description: '出来事の見出し（20字以内）'),
                description: '日記に書く出来事の候補（3〜4件）',
              ),
            },
            requiredProperties: ['topics'],
          ),
        ),
      ),
      _diaryModel = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: apiKey,
        systemInstruction: Content.system(
          AiInstructions.diaryWriter(roleFor(role).diaryStyle),
        ),
      ),
      _analysisModel = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: apiKey,
        systemInstruction: Content.system(
          '${AiInstructions.analyst(roleFor(role).analystStyle)}$analysisProfile',
        ),
      ),
      // 相談室で目標を詰めるモデル。人格はインタビュアーと同じ。
      // 返答（reply）と見立て（title 以下）を1回の応答でまとめて受け取るため、
      // 入れ子の任意オブジェクトにはせず全キー必須のフラットな形にしている
      // ―― 未確定のときは空文字・空配列が返るだけで、読み取り側の分岐が増えない。
      _consultModel = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: apiKey,
        systemInstruction: Content.system(
          '${roleFor(role).interviewerInstruction}$interviewProfile',
        ),
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json',
          responseSchema: Schema.object(
            properties: {
              'reply': Schema.string(
                description: '依頼人への返答。人格を保った1〜3文。問いかけは1つまで',
              ),
              'ready': Schema.boolean(description: '目標の見立てを提案できる状態か'),
              'title': Schema.string(description: '目標の一文。数字と期間を含める。未確定なら空文字'),
              'metric': Schema.string(description: '何がどうなったら達成かの基準。未確定なら空文字'),
              'deadline': Schema.string(
                description: '期限。YYYY-MM-DD 形式。決まっていなければ空文字',
              ),
              'actions': Schema.array(
                // 件数はプロンプトの【記録枠】で毎回伝える。responseSchema は
                // コンストラクタで一度だけ作られるため、ここに件数を書けない。
                description: '毎日の記録で追う項目。件数は指示文の【記録枠】に従う。未確定なら空配列',
                items: Schema.object(
                  properties: {
                    'label': Schema.string(
                      description: '記録する項目の名前。例「体重」「ジムに行く」',
                    ),
                    'type': Schema.enumString(
                      enumValues: ['numeric', 'check'],
                      description: 'numeric=数字を記録 / check=やったかどうかを記録',
                    ),
                    'unit': Schema.string(
                      description: 'numeric の単位。kg・歩・分など。check は空文字',
                    ),
                    'target': Schema.number(
                      description: 'numeric の目標値。決めないなら 0',
                    ),
                  },
                  requiredProperties: ['label', 'type', 'unit', 'target'],
                ),
              ),
              'questions': Schema.array(
                description: '日々の記録に加える問いを3〜5件。未確定なら空配列',
                items: Schema.string(description: '日々の記録で書き留める問い1件'),
              ),
            },
            requiredProperties: [
              'reply',
              'ready',
              'title',
              'metric',
              'deadline',
              'actions',
              'questions',
            ],
          ),
        ),
      );

  // ──────────────────────────────────────────────────────────────
  // 聴取
  // ──────────────────────────────────────────────────────────────

  // その日の記録から、日記に書く出来事の候補を挙げさせる。
  //
  // 失敗・空応答のときは空リストを返す。呼び出し側は記録のテキスト項目や
  // 定型の見出しで候補を補う（候補が出ないことで聴取を止めない）。
  Future<List<String>> generateTopicCandidates({
    required String recordContext,
    List<String> recentDiaries = const [],
    List<String> coveredTopics = const [],
  }) async {
    final prompt = DiaryPrompts.buildTopicPrompt(
      recordContext: recordContext,
      recentDiaries: recentDiaries,
      coveredTopics: coveredTopics,
    );
    final response = await _topicModel.generateContent([Content.text(prompt)]);
    final text = response.text?.trim() ?? '';
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic> && decoded['topics'] is List) {
        return [
          for (final raw in decoded['topics'] as List)
            if (raw is String && raw.trim().isNotEmpty) raw.trim(),
        ];
      }
    } catch (_) {
      // 読み取れない応答は候補なしとして扱う
    }
    return const [];
  }

  // 依頼人が選んだ出来事について、深掘りの入口になる質問を1つ返させる。
  // 空応答のときは空文字を返す。代わりの問いはロールの文面で呼び出し側が出す
  // （人格の台詞は lib/roles/ に置き、サービス層には持たせない）。
  Future<String> generateTopicQuestion({
    required String topic,
    required String recordContext,
  }) async {
    final prompt =
        '${AiInstructions.topicQuestionHint(roleFor(_role).interviewerInstruction)}\n\n'
        '${DiaryPrompts.buildTopicQuestionPrompt(topic: topic, recordContext: recordContext)}';
    final response = await _questionModel.generateContent([
      Content.text(prompt),
    ]);
    return response.text?.trim() ?? '';
  }

  // 1つの出来事についての会話を渡して、深掘り質問を生成させる。
  // 戻り値の sufficient が true の場合、これ以上の深掘りは不要（呼び出し側で打ち切る）。
  // JSONパースに失敗した場合は安全側に倒し、sufficient:true として扱う。
  Future<({bool sufficient, String question})> generateFollowUp(
    List<Map<String, String>> messages,
  ) async {
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

  // 聴取の会話から日記テキストを生成させる。
  // recordContext: その日の日々の記録（日記に使う項目だけを要約したもの）
  Future<String> generateDiary(
    List<Map<String, String>> messages, {
    String recordContext = '',
  }) async {
    final prompt = DiaryPrompts.buildDiaryPrompt(
      _buildHistory(messages),
      recordContext: recordContext,
    );
    final response = await _diaryModel.generateContent([Content.text(prompt)]);
    return response.text?.trim() ?? '日記を生成できませんでした。';
  }

  // 既存の日記と追加の聴取を統合して日記テキストを生成させる
  Future<String> generateDiaryWithExisting(
    String existingDiary,
    List<Map<String, String>> messages, {
    String recordContext = '',
  }) async {
    final prompt = DiaryPrompts.buildDiaryWithExistingPrompt(
      existingDiary,
      _buildHistory(messages),
      recordContext: recordContext,
    );
    final response = await _diaryModel.generateContent([Content.text(prompt)]);
    return response.text?.trim() ?? '日記を生成できませんでした。';
  }

  // メッセージリストを「探偵: ...」「依頼人: ...」形式の文字列に変換する
  String _buildHistory(List<Map<String, String>> messages) {
    return messages
        .map((m) => '${m['role'] == 'ai' ? '探偵' : '依頼人'}: ${m['text']}')
        .join('\n');
  }

  // ──────────────────────────────────────────────────────────────
  // 分析室
  // ──────────────────────────────────────────────────────────────

  // 直近の日々（mergeDays の結果）から所見テキストを生成させる。
  // fields: 値のキー → 記録項目。記録には項目 id しか入っていないため、
  // 渡さないとカスタム項目・目標の値は所見の材料から落ちる。
  Future<String> generateAnalysis(
    List<MapEntry<String, Map<String, dynamic>>> days, {
    Map<String, RecordField> fields = const {},
  }) async {
    final prompt = DiaryPrompts.buildAnalysisPrompt(days, fields: fields);
    final response = await _analysisModel.generateContent([
      Content.text(prompt),
    ]);
    return response.text?.trim() ?? '所見を生成できませんでした。';
  }

  // 今日1日と直近の日々からコメントテキストを生成させる。
  Future<String> generateDailyComment(
    Map<String, dynamic> today,
    List<MapEntry<String, Map<String, dynamic>>> recentDays, {
    Map<String, RecordField> fields = const {},
  }) async {
    final prompt = DiaryPrompts.buildDailyCommentPrompt(
      today,
      recentDays,
      fields: fields,
    );
    final response = await _analysisModel.generateContent([
      Content.text(prompt),
    ]);
    return response.text?.trim() ?? 'コメントを生成できませんでした。';
  }

  // ──────────────────────────────────────────────────────────────
  // 相談室
  // ──────────────────────────────────────────────────────────────

  // 相談室の会話から、探偵の返答と（まとまっていれば）目標の見立てを生成させる。
  //
  // 戻り値の goal は ready が true のときだけ非 null。
  // today には 'YYYY-MM-DD' を渡す（Goal.createdAt になり、プロンプトにも渡して
  // 期限の基準にさせる。日付の生成は呼び出し側の責務）。
  // target は見直す対象の目標。新しく立てるときは null。
  // otherGoals は同時に追っている他の目標（同じ狙いの事件を重ねて立てさせないため）。
  // actionBudget は毎日の記録に加えられる行動項目の残り枠。
  // forcePropose は「これで目標にする」を押されたとき。材料が足りなくても案を出させる。
  //
  // JSONパースに失敗しても会話は止めず、聞き返しを返す
  // （generateFollowUp が sufficient:true に倒して先へ進めるのと同じ、流れを止めない方針）。
  Future<({bool ready, String reply, Goal? goal})> consultGoal(
    List<Map<String, String>> messages, {
    required String today,
    Goal? target,
    List<Goal> otherGoals = const [],
    int actionBudget = kMaxGoalActions,
    bool forcePropose = false,
  }) async {
    // 残り枠が広くても、1目標あたりの上限は超えさせない
    final budget = actionBudget.clamp(0, kMaxGoalActions);
    final hint =
        AiInstructions.goalCoachHint(roleFor(_role).interviewerInstruction) +
        AiInstructions.goalActionBudgetHint(budget) +
        (forcePropose ? AiInstructions.goalForceProposeHint() : '');
    final body = GoalPrompts.buildConsultPrompt(
      _buildHistory(messages),
      today: today,
      targetGoalSummary: target?.promptSummary() ?? '',
      otherGoalsSummary: otherGoals
          .map((goal) => goal.promptHeadline())
          .where((line) => line.isNotEmpty)
          .join('\n'),
    );
    final response = await _consultModel.generateContent([
      Content.text('$hint\n\n$body'),
    ]);
    final text = response.text?.trim() ?? '';

    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        final reply = (decoded['reply'] as String?)?.trim() ?? '';
        if (decoded['ready'] == true) {
          final goal = Goal.fromAiMap(
            decoded,
            createdAt: today,
            maxActions: budget,
          );
          // タイトルが無ければ提案として成立しないので、会話の継続に倒す
          if (!goal.isEmpty) {
            return (
              ready: true,
              reply: reply.isNotEmpty ? reply : '筋書きはこうだ。',
              goal: goal,
            );
          }
        }
        return (
          ready: false,
          reply: reply.isNotEmpty ? reply : _consultFallbackReply,
          goal: null,
        );
      }
    } catch (_) {
      // 応答を読み取れないときは聞き返して会話を続ける
    }
    return (ready: false, reply: _consultFallbackReply, goal: null);
  }

  // 応答を読み取れなかったときの聞き返し。
  // ロールの口調には寄せない ―― 人格文面は lib/roles/ に集約しており、
  // サービス層がキャラクターの台詞を持ち始めると置き場所が二重になるため、
  // どのロールでも不自然でない最小限の一文にとどめる。
  static const String _consultFallbackReply = 'すまない、今の話を掴み損ねた。もう一度聞かせてくれ。';
}
