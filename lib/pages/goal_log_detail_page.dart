import 'package:flutter/material.dart';

import '../core/goal_progress.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/detective_text_styles.dart';
import '../models/goal.dart';
import '../services/firestore_service.dart';
import '../widgets/message_bubble.dart';
import '../widgets/section_label.dart';

// 目標1件・1日分の報告の詳細。記録一覧から行をタップして開く。
//
// その日の答えと、そのとき交わした会話を並べる。日記の詳細（DiaryDetailPage）が
// 生成された本文を見せるのに対し、こちらは本文を持たない ―― 目標の記録に
// 文面の生成は無く、残っているのは答えと会話そのものだから。
//
// 会話をタイプライターで流さないのは、これが読み返しの画面だから
// （animate: false）。初回の尋問と違って、既に読んだものを待たされる意味が無い。
class GoalLogDetailPage extends StatefulWidget {
  final String uid;
  final Goal goal;
  final String date; // 'YYYY-MM-DD'
  final Map<String, dynamic> entry;

  const GoalLogDetailPage({
    super.key,
    required this.uid,
    required this.goal,
    required this.date,
    required this.entry,
  });

  @override
  State<GoalLogDetailPage> createState() => _GoalLogDetailPageState();
}

class _GoalLogDetailPageState extends State<GoalLogDetailPage> {
  final FirestoreService _firestore = FirestoreService();

  bool _loading = true;
  bool _failed = false;
  List<Map<String, String>> _messages = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final messages = await _firestore.getGoalConversation(
        widget.uid,
        widget.goal.id,
        widget.date,
      );
      if (!mounted) return;
      setState(() {
        _messages = messages;
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

  // 'YYYY-MM-DD' → '2026年9月18日'。解釈できない形式はそのまま出す。
  String _formatDate() {
    final parts = widget.date.split('-');
    if (parts.length != 3) return widget.date;
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (month == null || day == null) return widget.date;
    return '${parts[0]}年$month月$day日';
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
              _formatDate(),
              style: DetectiveTextStyles.appBarTitle(color: c.appBarFg),
            ),
            const SizedBox(height: 2),
            Text(
              '― 報告の記録 ―',
              style: DetectiveTextStyles.appBarSubtitle(
                color: c.appBarSubtitle,
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          const SectionLabel('この日の報告', icon: Icons.fact_check_outlined),
          const SizedBox(height: 12),
          _buildAnswers(c),

          const SizedBox(height: 28),
          const SectionLabel('やりとり', icon: Icons.forum_outlined),
          const SizedBox(height: 12),

          if (_failed)
            Text(
              '会話を読み込めなかった。',
              style: TextStyle(fontSize: 12, color: c.textSecondary),
            )
          else if (_loading)
            Center(child: CircularProgressIndicator(color: c.gold))
          else if (_messages.isEmpty)
            Text(
              'この日の会話は記録されていない。',
              style: TextStyle(
                fontSize: 13,
                color: c.textSecondary,
                height: 1.5,
              ),
            )
          else
            for (final message in _messages)
              MessageBubble(
                role: message['role'] ?? 'ai',
                text: message['text'] ?? '',
                // 読み返しなので流さず、最初から全文を出す
                animate: false,
              ),
        ],
      ),
    );
  }

  // その日の答えを質問ごとに並べる。
  // スキップした項目と答えていない項目は同じ「—」にする ―― どちらも
  // 「記録が無い」であり、記録して0だったことと区別したいのはそこだから。
  Widget _buildAnswers(AppColors c) {
    final goal = widget.goal;
    if (goal.actions.isEmpty) {
      return Text(
        '毎日する質問は設定されていない。',
        style: TextStyle(fontSize: 13, color: c.textSecondary),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.cardBorder),
      ),
      child: Column(
        children: [
          for (var i = 0; i < goal.actions.length; i++) ...[
            if (i > 0) Divider(height: 1, color: c.cardBorder),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      goal.actions[i].label,
                      style: TextStyle(fontSize: 13, color: c.textSecondary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _valueFor(goal.actions[i]),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: c.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _valueFor(GoalAction action) {
    if (action.isNumeric) {
      final value = numericFor(widget.entry, action.answerKey);
      if (value != null) {
        final text = value == value.roundToDouble()
            ? value.toStringAsFixed(0)
            : value.toStringAsFixed(1);
        return action.unit.isEmpty ? text : '$text${action.unit}';
      }
      // 数字として控えられなかった自由記述は、書かれたままを出す
      return answerFor(widget.entry, action.answerKey) ?? '—';
    }
    return answerFor(widget.entry, action.answerKey) ?? '—';
  }
}
