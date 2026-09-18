import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/detective_text_styles.dart';
import '../models/mbti_type.dart';
import '../models/self_analysis.dart';
import '../services/firestore_service.dart';
import '../widgets/settings_section.dart';

// 依頼人（ユーザー）自身のプロフィールを登録する画面。
// ホームの「捜査資料」セクションから push で開く。
//
// ここで登録した内容は、トグルの状態に応じて探偵AIのプロンプト（systemInstruction）へ
// 差し込まれ、深掘り質問や所見の切り口に反映される。
// 保存先は users/{uid}/self-analysis/profile で、記録設定（UserSettings）とは別コレクション。
//
// 第一弾はMBTIのみ。今後項目が増えてもこのページにセクションを足していけばよい。
class SelfAnalysisPage extends StatefulWidget {
  final String uid;

  const SelfAnalysisPage({super.key, required this.uid});

  @override
  State<SelfAnalysisPage> createState() => _SelfAnalysisPageState();
}

class _SelfAnalysisPageState extends State<SelfAnalysisPage> {
  SelfAnalysis _selfAnalysis = SelfAnalysis.defaults();
  bool _isLoading = true;
  bool _isSaving = false; // 保存中フラグ（AppBarにスピナーを表示するために使用）

  final FirestoreService _firestore = FirestoreService();

  @override
  void initState() {
    super.initState();
    _load();
  }

  // Firestoreから現在の自己分析を読み込む（未登録ならデフォルトが返る）
  Future<void> _load() async {
    final selfAnalysis = await _firestore.getSelfAnalysis(widget.uid);
    if (!mounted) return;
    setState(() {
      _selfAnalysis = selfAnalysis;
      _isLoading = false;
    });
  }

  // 変更をFirestoreに即時保存する（設定画面・探偵選択画面と同じ流儀）
  Future<void> _save(SelfAnalysis next) async {
    setState(() {
      _selfAnalysis = next;
      _isSaving = true;
    });
    await _firestore.saveSelfAnalysis(widget.uid, next);
    if (!mounted) return;
    setState(() => _isSaving = false);
  }

  // MBTIを選ぶ。選択中のものを再タップした場合は登録を解除する
  // （「やっぱりAIに渡したくない」を1タップで実現できるようにするため）。
  Future<void> _selectMbti(String key) async {
    final next = _selfAnalysis.mbti == key ? '' : key;
    await _save(_selfAnalysis.copyWith(mbti: next));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final types = kMbtiTypes.values.toList(growable: false);
    // 未登録のうちは共有トグルを操作しても渡すものが無いため、無効化して状態を見せる
    final hasProfile = _selfAnalysis.hasProfile;

    return Scaffold(
      backgroundColor: c.background,

      // ── AppBar ──────────────────────────────────────────────
      // 他のページと同じくサブタイトル付きで探偵事務所の雰囲気を揃える
      appBar: AppBar(
        backgroundColor: c.appBarBg,
        foregroundColor: c.appBarFg,
        elevation: 0,
        toolbarHeight: 64,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '自己分析',
              style: DetectiveTextStyles.appBarTitle(color: c.appBarFg),
            ),
            const SizedBox(height: 2),
            Text(
              '― 依頼人の人物像を記録する ―',
              style: DetectiveTextStyles.appBarSubtitle(
                color: c.appBarSubtitle,
              ),
            ),
          ],
        ),
        actions: [
          // 保存中はAppBar右端にゴールドのスピナーを表示する
          if (_isSaving)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: c.goldLight,
                  strokeWidth: 2,
                ),
              ),
            ),
        ],
      ),

      // ── Body ────────────────────────────────────────────────
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: c.gold))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // ── セクション1: MBTI ──────────────────────────
                const SectionHeader(
                  title: '◆ MBTI',
                  subtitle: '当てはまるものを1つ選ぶ（もう一度タップで解除）',
                ),
                const SizedBox(height: 12),
                for (final type in types) ...[
                  _MbtiCard(
                    type: type,
                    selected: type.key == _selfAnalysis.mbti,
                    onTap: () => _selectMbti(type.key),
                  ),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 16),

                // ── セクション2: 探偵への共有 ───────────────────
                const SectionHeader(
                  title: '◆ 探偵への共有',
                  subtitle: 'この情報を探偵AIに渡すかどうか',
                ),
                const SizedBox(height: 8),
                SettingsCard(
                  children: [
                    SettingsSwitchTile(
                      title: '捜査中の深掘りに活かす',
                      subtitle: '質問の切り口を人物像に合わせます',
                      value: _selfAnalysis.shareWithInterview,
                      onChanged: hasProfile
                          ? (v) => _save(
                              _selfAnalysis.copyWith(shareWithInterview: v),
                            )
                          : null,
                    ),
                    Divider(height: 1, color: c.cardBorder),
                    SettingsSwitchTile(
                      title: '事件簿の分析に活かす',
                      subtitle: '所見と今日のコメントの語り口に反映します',
                      value: _selfAnalysis.shareWithAnalysis,
                      onChanged: hasProfile
                          ? (v) => _save(
                              _selfAnalysis.copyWith(shareWithAnalysis: v),
                            )
                          : null,
                    ),
                  ],
                ),
                if (!hasProfile) ...[
                  const SizedBox(height: 10),
                  Text(
                    'MBTIを登録すると共有の設定ができる。',
                    style: TextStyle(fontSize: 12, color: c.textSecondary),
                  ),
                ],
                const SizedBox(height: 32),
              ],
            ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// MBTI1タイプ分の選択カード
//
// 探偵キャラ選択画面の _RoleCard と同じ書類風デザイン。
// タイプコード（太字）＋通称、その下に傾向の説明を出し、
// 選択中はカード枠をゴールドにして強調する。
// ──────────────────────────────────────────────────────────────
class _MbtiCard extends StatelessWidget {
  final MbtiType type;
  final bool selected;
  final VoidCallback onTap;

  const _MbtiCard({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(
          color: selected ? c.gold : c.cardBorder,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 左端のゴールドアクセントボーダー
              Container(width: 4, color: c.gold),

              // カード本文
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      // タイプコード + 通称 + 傾向の説明
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 文字サイズを上げても overflow しないよう Wrap で折り返す
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.end,
                              spacing: 8,
                              children: [
                                Text(
                                  type.key,
                                  style: DetectiveTextStyles.cardTitle(
                                    color: c.textPrimary,
                                  ),
                                ),
                                Text(
                                  type.label,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: c.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              type.description,
                              style: TextStyle(
                                fontSize: 12,
                                color: c.textSecondary,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),

                      // 選択状態マーク
                      Icon(
                        selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: selected ? c.gold : c.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
