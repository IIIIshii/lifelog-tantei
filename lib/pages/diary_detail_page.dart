import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/detective_text_styles.dart';
import '../services/firestore_service.dart';
import 'diary_edit_page.dart';
import 'diary_page.dart';

// 特定の日の日記を事件報告書として全文表示する詳細ページ。
//
// 直し方は2通りある。本文を手で書き換える DiaryEditPage と、探偵の質問に
// 答え直して生成しなおす DiaryPage。どちらも同じ重みで並べているのは、
// 一字だけ直したいときと、記録そのものを取り直したいときで要るものが違うため。
//
// StatefulWidget なのは、どちらかで直して戻ってきたときに本文を取り直すため。
// 一覧（DiaryListPage）は Firestore の snapshot を直接見ているので自動で追いつくが、
// この画面は開いた時点の本文を受け取っているだけで、放っておくと古い文面が残る。
class DiaryDetailPage extends StatefulWidget {
  final String date; // 表示する日付（YYYY-MM-DD）
  final String diary; // 表示する日記テキスト
  final String uid; // 編集保存に必要なユーザーID
  final FirestoreService firestore;

  const DiaryDetailPage({
    super.key,
    required this.date,
    required this.diary,
    required this.uid,
    required this.firestore,
  });

  @override
  State<DiaryDetailPage> createState() => _DiaryDetailPageState();
}

class _DiaryDetailPageState extends State<DiaryDetailPage> {
  late String _diary = widget.diary;

  // YYYY-MM-DD → YYYY年MM月DD日 に整形する（diary_list_pageと同じ形式）
  String _formatDate(String raw) {
    final parts = raw.split('-');
    if (parts.length != 3) return raw;
    return '${parts[0]}年${parts[1]}月${parts[2]}日';
  }

  // 直しから戻ってきたときに本文を取り直す。
  // 読めなかった場合は画面に出ている文面を保つ（空にして驚かせない）。
  Future<void> _reload() async {
    try {
      final latest = await widget.firestore.getTodayDiary(
        widget.uid,
        widget.date,
      );
      if (!mounted || latest == null) return;
      setState(() => _diary = latest);
    } catch (_) {
      // 表示は保ったままにする
    }
  }

  // 本文を手で書き換える
  void _openEdit() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => DiaryEditPage(
          uid: widget.uid,
          today: widget.date,
          firestore: widget.firestore,
          initialDiary: _diary,
        ),
      ),
    ).then((_) => _reload());
  }

  // 探偵に聞き直して報告書を作り直す。
  // 既に日記のある日なので、DiaryPage 側では今日の分と同じ
  // 「追記する / いちから作り直す / 日記を確認する」の分岐に合流する。
  void _openRevisit() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => DiaryPage(date: widget.date)),
    ).then((_) => _reload());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final displayDiary = _diary.trim().isEmpty ? '（本文なし）' : _diary;
    return Scaffold(
      backgroundColor: c.background,

      // ── AppBar ──────────────────────────────────────────────
      // 日付を整形して表示し、サブタイトルで「事件報告書」であることを示す
      appBar: AppBar(
        backgroundColor: c.appBarBg,
        foregroundColor: c.appBarFg,
        elevation: 0,
        toolbarHeight: 64,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _formatDate(widget.date),
              style: DetectiveTextStyles.appBarTitle(color: c.appBarFg),
            ),
            const SizedBox(height: 2),
            Text(
              '― 事件報告書 ―',
              style: DetectiveTextStyles.appBarSubtitle(
                color: c.appBarSubtitle,
              ),
            ),
          ],
        ),
      ),

      // ── Body ────────────────────────────────────────────────
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Container(
                decoration: BoxDecoration(
                  color: c.cardBg,
                  borderRadius: BorderRadius.circular(4),
                  // ゴールドの枠線でDiaryCardと同じ「重要書類」感を表現する
                  border: Border.all(color: c.gold, width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── ヘッダー行（DiaryCardと同じデザイン） ────────
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: c.gold)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.description, color: c.gold, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            '事件報告書',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: c.gold,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const Spacer(),
                          // CLOSEDバッジ
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(color: c.gold),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Text(
                              'CLOSED',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: c.gold,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── 日記本文（全文表示） ──────────────────────────
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        displayDiary,
                        style: TextStyle(
                          fontSize: 16,
                          color: c.textPrimary,
                          height: 1.8, // 行間を広めにとって読みやすくする
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── 直し方の2択 ──────────────────────────────────────
          // どちらが主とも決めていないので、同じ見た目で横に並べる。
          // 一字だけ直したいときと、記録そのものを取り直したいときで
          // 要るものが違い、どちらが多いとも言えないため。
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: _FixButton(label: '手で編集', onPressed: _openEdit),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _FixButton(label: '探偵に聞き直す', onPressed: _openRevisit),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// 直し方のボタン1つ。見分けるのはラベルだけで、見た目に重みは付けない。
class _FixButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _FixButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: c.gold,
        foregroundColor: c.onAccent,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      // 端末幅が狭くてもボタンが縦に伸びないよう1行に収める
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
      ),
    );
  }
}
