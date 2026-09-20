import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../models/goal.dart';
import '../models/self_analysis.dart';
import '../prompts/ai_instructions.dart';
import '../prompts/diary_prompts.dart';
import '../prompts/goal_prompts.dart';
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
  // 自由記述への短いリアクション（相槌）を返すモデル。プレーンテキスト出力。
  final GenerativeModel _reactionModel;
  // 過去ログを読み、今日の日記を書くための質問リストを返すモデル。
  final GenerativeModel _memoryQuestionModel;
  // 相談室で目標を詰めるモデル。返答と見立てを構造化して返す。
  final GenerativeModel _consultModel;

  final String _role;

  // 自己分析（MBTI等）を systemInstruction の末尾へ差し込むためのブロック。
  // 初期化子リストでは計算ができないため、factory で組み立ててから private コンストラクタへ渡す。
  // selfAnalysis を省略した場合は従来どおり何も差し込まれない。
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
      // インタビュアーと同じ人格指示だが、JSON構造化はせずプレーンテキストで相槌を返す
      _reactionModel = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: apiKey,
        systemInstruction: Content.system(
          '${roleFor(role).interviewerInstruction}$interviewProfile',
        ),
      ),
      _memoryQuestionModel = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: apiKey,
        systemInstruction: Content.system(
          '${roleFor(role).interviewerInstruction}$interviewProfile',
        ),
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json',
          responseSchema: Schema.object(
            properties: {
              'questions': Schema.array(
                items: Schema.string(description: '依頼人へ投げる質問文'),
                description: '今日の日記を書くための質問リスト',
              ),
            },
            requiredProperties: ['questions'],
          ),
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
                description: '独自質問リストへ提案する問いを3〜5件。未確定なら空配列',
                items: Schema.string(description: '日々の記録で投げかける質問1件'),
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

  // 会話履歴を渡して深掘り質問をGeminiに生成させる。
  // followUpHint を隠し指示として会話履歴に付加し、UIには表示しない。
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

  // 会話履歴を渡して、直前の依頼人の証言への短いリアクション（相槌）を生成させる。
  // 自由記述の回答に対してのみ呼ぶ（ボタン選択はロール定義の固定文面を使う）。
  // 失敗・空応答時は空文字を返し、呼び出し側でリアクション表示をスキップさせる。
  Future<String> generateReaction(List<Map<String, String>> messages) async {
    final history = _buildHistory(messages);
    final prompt =
        '${AiInstructions.reactionHint(roleFor(_role).interviewerInstruction)}\n\n以下が依頼人の証言です：\n$history';
    final response = await _reactionModel.generateContent([
      Content.text(prompt),
    ]);
    return response.text?.trim() ?? '';
  }

  Future<List<String>> generateMemoryQuestions(
    List<MapEntry<String, Map<String, dynamic>>> entries,
  ) async {
    final prompt = DiaryPrompts.buildMemoryQuestionPrompt(entries);
    final response = await _memoryQuestionModel.generateContent([
      Content.text(prompt),
    ]);
    final text = response.text?.trim() ?? '';
    final questions = <String>[];
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        final rawQuestions = decoded['questions'];
        if (rawQuestions is List) {
          for (final q in rawQuestions) {
            if (q is String && q.trim().isNotEmpty) {
              questions.add(q.trim());
            }
          }
        }
      }
    } catch (_) {
      // パースできない場合は下のフォールバックで最低限の質問を用意する
    }

    const fallback = [
      '今朝はどんなふうに一日が始まった？',
      'いつもと少し違った場面はあったか？',
      '誰かとのやりとりで覚えていることはあるか？',
      '食事や移動、作業の中で印象に残ったものは？',
      '今の気分に近い言葉を選ぶなら何だ？',
      '明日の自分に残しておきたい手がかりはあるか？',
    ];

    for (final q in fallback) {
      if (questions.length >= 5) break;
      questions.add(q);
    }
    return questions.take(6).toList(growable: false);
  }

  // 会話履歴から日記テキストをGeminiに生成させる。
  // additionalContext: カスタム質問・思い出しアシストの回答など、追加で含めるコンテキスト
  Future<String> generateDiary(
    List<Map<String, String>> messages, {
    String additionalContext = '',
  }) async {
    final history = _buildHistory(messages);
    final prompt = DiaryPrompts.buildDiaryPrompt(
      history,
      additionalContext: additionalContext,
    );
    final response = await _diaryModel.generateContent([Content.text(prompt)]);
    return response.text?.trim() ?? '日記を生成できませんでした。';
  }

  // 既存の日記と追記インタビューの会話を統合して日記テキストをGeminiに生成させる
  // additionalContext: カスタム質問・思い出しアシストの回答など、追加で含めるコンテキスト
  Future<String> generateDiaryWithExisting(
    String existingDiary,
    List<Map<String, String>> messages, {
    String additionalContext = '',
  }) async {
    final history = _buildHistory(messages);
    final prompt = DiaryPrompts.buildDiaryWithExistingPrompt(
      existingDiary,
      history,
      additionalContext: additionalContext,
    );
    final response = await _diaryModel.generateContent([Content.text(prompt)]);
    return response.text?.trim() ?? '日記を生成できませんでした。';
  }

  // 直近のエントリ群（日付→データ）から所見テキストをGeminiに生成させる。
  // 呼び出し側は FirestoreService.getRecentEntries の戻り値をそのまま渡せる。
  Future<String> generateAnalysis(
    List<MapEntry<String, Map<String, dynamic>>> entries,
  ) async {
    final prompt = DiaryPrompts.buildAnalysisPrompt(entries);
    final response = await _analysisModel.generateContent([
      Content.text(prompt),
    ]);
    return response.text?.trim() ?? '所見を生成できませんでした。';
  }

  // メッセージリストを「探偵: ...」「依頼人: ...」形式の文字列に変換する
  String _buildHistory(List<Map<String, String>> messages) {
    return messages
        .map((m) => '${m['role'] == 'ai' ? '探偵' : '依頼人'}: ${m['text']}')
        .join('\n');
  }

  // 今日のエントリと直近14日分からコメントテキストをGeminiに生成させる。
  Future<String> generateDailyComment(
    Map<String, dynamic> todayEntry,
    List<MapEntry<String, Map<String, dynamic>>> recentEntries,
  ) async {
    final prompt = DiaryPrompts.buildDailyCommentPrompt(
      todayEntry,
      recentEntries,
    );
    final response = await _analysisModel.generateContent([
      Content.text(prompt),
    ]);
    return response.text?.trim() ?? 'コメントを生成できませんでした。';
  }

  // 相談室の会話から、探偵の返答と（まとまっていれば）目標の見立てを生成させる。
  //
  // 戻り値の goal は ready が true のときだけ非 null。
  // today には 'YYYY-MM-DD' を渡す（Goal.createdAt になる。日付の生成は呼び出し側の責務）。
  // target は見直す対象の目標。新しく立てるときは null。
  // otherGoals は同時に追っている他の目標（同じ狙いの事件を重ねて立てさせないため）。
  // actionBudget は毎日の記録に加えられる行動項目の残り枠。
  // forcePropose は「これで目標にする」を押されたとき。材料が足りなくても案を出させる。
  //
  // 目標を文字列ではなく Goal のまま受けるのは、要約の作り方と件数の決め方を
  // この層にまとめ、呼び出し側がプロンプトの形を知らずに済むようにするため
  // （GoalPrompts を呼ぶのはもともとこの層の仕事）。
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
