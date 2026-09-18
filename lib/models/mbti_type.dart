// MBTI 16タイプのレジストリ。
// lib/roles/roles.dart（探偵ロール）と同じく、定義をここ1か所に集約し、
// 一覧UI・AIへ渡す文面の双方がこの静的データだけを参照する。
//
// description は「自己分析ページのカードに出す一言」と「探偵AIへ渡す傾向の説明」を兼ねる。
// 断定・評価を含めず、行動の傾向だけを短く書くこと（AIのレッテル貼りを誘発しないため）。
class MbtiType {
  final String key; // 'INTJ' など4文字の大文字。SelfAnalysis.mbti と一致させる
  final String label; // 日本語の通称（建築家 など）
  final String description; // 20〜30字程度の傾向説明

  const MbtiType({
    required this.key,
    required this.label,
    required this.description,
  });
}

// 選択キー → MbtiType 定義。自己分析ページの一覧もこの順序で表示する。
// 並びは一般的な4グループ（分析家 NT / 外交官 NF / 番人 SJ / 探検家 SP）の順。
const Map<String, MbtiType> kMbtiTypes = {
  // ── 分析家（NT） ──
  'INTJ': MbtiType(
    key: 'INTJ',
    label: '建築家',
    description: '構想を練り、長期的な筋道を立てて動く',
  ),
  'INTP': MbtiType(key: 'INTP', label: '論理学者', description: '仕組みの理屈を突き詰めて考える'),
  'ENTJ': MbtiType(key: 'ENTJ', label: '指揮官', description: '目標を定め、周囲を巻き込んで進める'),
  'ENTP': MbtiType(
    key: 'ENTP',
    label: '討論者',
    description: '新しい発想を試し、対話から着想を得る',
  ),

  // ── 外交官（NF） ──
  'INFJ': MbtiType(
    key: 'INFJ',
    label: '提唱者',
    description: '静かに理想を抱き、人の機微を汲み取る',
  ),
  'INFP': MbtiType(
    key: 'INFP',
    label: '仲介者',
    description: '自分の価値観を大切に、内側で感じ取る',
  ),
  'ENFJ': MbtiType(key: 'ENFJ', label: '主人公', description: '人の可能性に目を向け、場をまとめる'),
  'ENFP': MbtiType(
    key: 'ENFP',
    label: '運動家',
    description: '興味の赴くままに動き、人と熱を分かち合う',
  ),

  // ── 番人（SJ） ──
  'ISTJ': MbtiType(key: 'ISTJ', label: '管理者', description: '決めた手順を守り、着実に積み上げる'),
  'ISFJ': MbtiType(key: 'ISFJ', label: '擁護者', description: '身近な人を気遣い、陰から支える'),
  'ESTJ': MbtiType(key: 'ESTJ', label: '幹部', description: '段取りを整え、現実的に物事を仕切る'),
  'ESFJ': MbtiType(
    key: 'ESFJ',
    label: '領事官',
    description: '周囲との調和を保ち、場の空気を整える',
  ),

  // ── 探検家（SP） ──
  'ISTP': MbtiType(key: 'ISTP', label: '巨匠', description: '手を動かして確かめ、その場で対処する'),
  'ISFP': MbtiType(key: 'ISFP', label: '冒険家', description: '感覚を頼りに、自分のペースで味わう'),
  'ESTP': MbtiType(key: 'ESTP', label: '起業家', description: '今この瞬間に反応し、行動で切り開く'),
  'ESFP': MbtiType(
    key: 'ESFP',
    label: 'エンターテイナー',
    description: 'その場を楽しみ、人との時間で満たされる',
  ),
};

// 選択キーから MbtiType を引く。
// roleFor() と違いデフォルトへフォールバックしない ―― 自己分析は「未登録」が正常な状態で、
// 未登録のまま何かのタイプとして扱われるとAIに誤った人物像が渡るため。
MbtiType? mbtiTypeFor(String? key) => key == null ? null : kMbtiTypes[key];
