import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/detective_text_styles.dart';
import '../models/analysis_entry.dart';
import '../services/firestore_service.dart';

// 過去の所見の綴り。分析室で探偵が書いた所見・今日のコメントを新しい順に並べる。
//
// 一覧では書き出しの数行だけを見せ、タップで全文を開く。所見は1件が数百字あり、
// 全文を並べると何件目を読んでいるのか分からなくなるため。
class AnalysisHistoryPage extends StatefulWidget {
  final String uid;

  const AnalysisHistoryPage({super.key, required this.uid});

  @override
  State<AnalysisHistoryPage> createState() => _AnalysisHistoryPageState();
}

class _AnalysisHistoryPageState extends State<AnalysisHistoryPage> {
  final FirestoreService _firestore = FirestoreService();

  // 1画面で読み返す分には十分な件数。古いものはここで打ち切る
  static const int _limit = 100;

  bool _loading = true;
  bool _failed = false;
  List<AnalysisEntry> _entries = const [];
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final entries = await _firestore.getAnalyses(widget.uid, limit: _limit);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
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
              '所見の綴り',
              style: DetectiveTextStyles.appBarTitle(color: c.appBarFg),
            ),
            const SizedBox(height: 2),
            Text(
              '― 過去の推理を読み返す ―',
              style: DetectiveTextStyles.appBarSubtitle(
                color: c.appBarSubtitle,
              ),
            ),
          ],
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: c.gold))
          : RefreshIndicator(
              color: c.gold,
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                children: [
                  if (_failed)
                    _Notice(message: '綴りを読み込めなかった。引き下げてもう一度試してくれ。')
                  else if (_entries.isEmpty)
                    _Notice(message: 'まだ所見は書かれていない。分析室で探偵に推理させてくれ。')
                  else
                    for (final entry in _entries) ...[
                      _EntryCard(
                        entry: entry,
                        expanded: _expanded.contains(entry.id),
                        onTap: () => setState(() {
                          _expanded.contains(entry.id)
                              ? _expanded.remove(entry.id)
                              : _expanded.add(entry.id);
                        }),
                      ),
                      const SizedBox(height: 10),
                    ],
                ],
              ),
            ),
    );
  }
}

// 所見1件。閉じているときは書き出しの3行、開くと全文。
class _EntryCard extends StatelessWidget {
  final AnalysisEntry entry;
  final bool expanded;
  final VoidCallback onTap;

  const _EntryCard({
    required this.entry,
    required this.expanded,
    required this.onTap,
  });

  String _when() {
    final at = entry.generatedAt;
    if (at == null) return entry.date;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${at.year}/${two(at.month)}/${two(at.day)} '
        '${two(at.hour)}:${two(at.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(4)),
        side: BorderSide(color: c.cardBorder),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    entry.kind == AnalysisKind.daily
                        ? Icons.today_outlined
                        : Icons.search,
                    size: 14,
                    color: c.gold,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      analysisKindLabel(
                        entry.kind,
                        periodDays: entry.periodDays,
                      ),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: c.gold,
                      ),
                    ),
                  ),
                  Text(
                    _when(),
                    style: TextStyle(fontSize: 11, color: c.textSecondary),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: c.textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                entry.text,
                maxLines: expanded ? null : 3,
                overflow: expanded ? null : TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: c.textPrimary,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final String message;

  const _Notice({required this.message});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.cardBorder),
      ),
      child: Text(
        message,
        style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.5),
      ),
    );
  }
}
