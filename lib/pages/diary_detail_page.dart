import 'package:flutter/material.dart';

import '../core/daily_record.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/detective_text_styles.dart';
import '../models/record_field.dart';
import '../services/firestore_service.dart';
import 'diary_edit_page.dart';
import 'diary_page.dart';
import 'record_sheet_page.dart';

// 特定の日の事件報告書。その日の日記本文と、日々の記録（事実）を1枚に並べる。
//
// 直し方は3通りある。本文を手で書き換える DiaryEditPage、探偵に聞き直して
// まとめ直す DiaryPage、事実の方を直す RecordSheetPage。
//
// StatefulWidget なのは、どれかで直して戻ってきたときに読み直すため。
// 一覧（事件簿アーカイブ）は snapshot を直接見ているので自動で追いつくが、
// この画面は開いた時点の内容を持っているだけで、放っておくと古いまま残る。
class DiaryDetailPage extends StatefulWidget {
  final String date; // 表示する日付（YYYY-MM-DD）
  final String diary; // 一覧から受け取った本文（読み直すまでの表示に使う）
  final String uid;
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
  List<String> _topics = const [];
  // その日の記録（記入済みの項目だけ、表に並んでいた順で）
  List<({RecordField field, String value})> _facts = const [];
  bool _loadingFacts = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  // YYYY-MM-DD → YYYY年MM月DD日 に整形する（CaseArchiveTile と同じ形式）
  String _formatDate(String raw) {
    final parts = raw.split('-');
    if (parts.length != 3) return raw;
    return '${parts[0]}年${parts[1]}月${parts[2]}日';
  }

  // 本文・出来事・記録を読み直す。
  // 読めなかった場合は画面に出ている内容を保つ（空にして驚かせない）。
  Future<void> _reload() async {
    try {
      final diaryFuture = widget.firestore.getDiary(widget.uid, widget.date);
      final recordFuture = widget.firestore.getRecord(widget.uid, widget.date);
      final fieldsFuture = widget.firestore.getFields(widget.uid);
      final goalsFuture = widget.firestore.getAllGoals(widget.uid);
      final diary = await diaryFuture;
      final record = await recordFuture;
      final fields = await fieldsFuture;
      final goals = await goalsFuture;
      if (!mounted) return;

      // 使わなくなった項目・閉じた目標の項目も、その日に値があれば出す
      // （過去の日の事実としては意味がある）
      final index = fieldIndex(fields, [...goals.active, ...goals.closed]);
      final facts = <({RecordField field, String value})>[];
      for (final field in index.values) {
        final text = formatValue(field, valueOf(record, field.id));
        if (text != null) facts.add((field: field, value: text));
      }

      setState(() {
        final text = (diary?['text'] as String?)?.trim();
        if (text != null && text.isNotEmpty) _diary = text;
        _topics =
            (diary?['topics'] as List<dynamic>?)?.whereType<String>().toList() ??
            const [];
        _facts = facts;
        _loadingFacts = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingFacts = false);
    }
  }

  void _openEdit() {
    Navigator.push(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => DiaryEditPage(
          uid: widget.uid,
          date: widget.date,
          firestore: widget.firestore,
          initialDiary: _diary,
        ),
      ),
    ).then((_) => _reload());
  }

  // 探偵に聞き直して報告書を作り直す。
  // 既に日記のある日なので、聴取の側で「出来事を足す / 作り直す」を選ぶ。
  void _openRevisit() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => DiaryPage(date: widget.date)),
    ).then((_) => _reload());
  }

  void _openRecord() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => RecordSheetPage(uid: widget.uid, date: widget.date),
      ),
    ).then((_) => _reload());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final displayDiary = _diary.trim().isEmpty ? '（本文なし）' : _diary;
    return Scaffold(
      backgroundColor: c.background,
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
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ReportCard(diary: displayDiary, topics: _topics),
                  const SizedBox(height: 20),
                  _FactsCard(
                    loading: _loadingFacts,
                    facts: _facts,
                    onOpenRecord: _openRecord,
                  ),
                ],
              ),
            ),
          ),

          // ── 本文の直し方の2択 ────────────────────────────────
          // どちらが主とも決めていないので、同じ見た目で横に並べる。
          // 一字だけ直したいときと、聞き直して書き直したいときで要るものが違うため。
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

// 日記本文のカード（DiaryCard と同じ「重要書類」のデザイン）。
class _ReportCard extends StatelessWidget {
  final String diary;
  final List<String> topics;

  const _ReportCard({required this.diary, required this.topics});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.gold, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
          // 聴取で話した出来事。本文のどこに何が書かれているかの目次になる
          if (topics.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final topic in topics)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: c.goldLight,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Text(
                        topic,
                        style: TextStyle(fontSize: 11, color: c.caseNumberFg),
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              diary,
              style: TextStyle(fontSize: 16, color: c.textPrimary, height: 1.8),
            ),
          ),
        ],
      ),
    );
  }
}

// その日の日々の記録。記入済みの項目を「名前 … 値」で並べる。
class _FactsCard extends StatelessWidget {
  final bool loading;
  final List<({RecordField field, String value})> facts;
  final VoidCallback onOpenRecord;

  const _FactsCard({
    required this.loading,
    required this.facts,
    required this.onOpenRecord,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 4, 6),
            child: Row(
              children: [
                Icon(Icons.fact_check_outlined, color: c.gold, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'この日の記録',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: c.gold,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onOpenRecord,
                  child: Text(
                    '記録を直す',
                    style: TextStyle(fontSize: 12, color: c.gold),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: c.cardBorder),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: loading
                ? Text(
                    '照会中…',
                    style: TextStyle(fontSize: 13, color: c.textSecondary),
                  )
                : facts.isEmpty
                ? Text(
                    'この日の記録はまだ無い。',
                    style: TextStyle(fontSize: 13, color: c.textSecondary),
                  )
                : Column(
                    children: [
                      for (final fact in facts)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 120,
                                child: Text(
                                  fact.field.isGoal
                                      ? '${fact.field.label}（目標）'
                                      : fact.field.label,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: c.textSecondary,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  fact.value,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: c.textPrimary,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
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
