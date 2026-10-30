// AI（Gemini）へ送られる内容の一覧。設定の「AIへの送信について」に表示する。
//
// なぜ画面から切り出すか：
// 日記と記録は個人的な内容で、何が送られるかは利用者に伝える必要がある。
// 文面を画面のコードに埋めると、送る内容を増やしたときに説明の更新を忘れても
// 気づけない。一覧をデータにしておけば、項目が空でないことなどをテストで見張れる。
//
// 送信の実態は gemini_service.dart の各メソッドと、渡す側のプロンプト
// （diary_prompts.dart）に基づく。送る内容を変えたら、ここも直すこと。

/// 送信先の名前。画面の説明文で使う。
const aiProviderName = 'Google の Gemini';

/// AI へ送られる内容の1項目。
class AiDataItem {
  /// 何が送られるか（例: 日々の記録）。
  final String label;

  /// その中身の具体例。
  final String detail;

  /// AI がそれを何に使うか。
  final String usedFor;

  /// 送られる条件や例外。無ければ空。
  final String note;

  const AiDataItem({
    required this.label,
    required this.detail,
    required this.usedFor,
    this.note = '',
  });
}

const aiDataItems = <AiDataItem>[
  AiDataItem(
    label: '日々の記録',
    detail: '睡眠時間・気分・自分で足した項目・目標の行動項目に入れた値',
    usedFor: '話題の候補出し、日記づくり、所見と今日のコメント',
    note: '「日記に使わない」にした項目は、日記の材料から外れます',
  ),
  AiDataItem(
    label: '聴取での会話',
    detail: 'あなたの答えと、探偵の質問',
    usedFor: '深掘りの質問づくり、日記づくり',
  ),
  AiDataItem(
    label: '日記の本文',
    detail: 'できあがった日記の文章',
    usedFor: '同じ日の追加の聴取との統合、話題の候補づくりの参考、直近の所見とコメント',
  ),
  AiDataItem(
    label: '「探偵に話す」で話した内容',
    detail: '記録の表に向けてまとめて話した内容',
    usedFor: '記録の項目への振り分け',
  ),
  AiDataItem(
    label: '目標の相談',
    detail: '相談室でのやりとり',
    usedFor: '目標の見立て',
  ),
  AiDataItem(
    label: '自己分析（MBTI）',
    detail: '登録した性格タイプ',
    usedFor: '質問の切り口、所見とコメントの語り口',
    note: '登録したときだけ送られます。登録後は「探偵への共有」が初期でオンです（自己分析の画面で切れます）',
  ),
];
