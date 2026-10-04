import 'package:flutter/material.dart';

import '../core/goal_progress.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/detective_text_styles.dart';
import '../models/goal.dart';
import '../services/firestore_service.dart';
import '../widgets/section_label.dart';
import 'goal_log_detail_page.dart';

// 目標1件の追跡記録の一覧。相談室で事件をタップして開く。
//
// 期間は着手日（createdAt）から今日まで。直近N日に切らないのは、目標が
// アプリ全体で「着手から n 日」で語られているため ―― 直近N日だと着手直後は
// ほぼ空になり、長く続けた目標では最初の変化が見えなくなる。
//
// 記録の無い日は行にしない。数ヶ月続く目標で空行が数十行並ぶと、実際に答えた日が
// その中に埋もれる。欠けは見出しの「記録 12 / 45日」で数として伝える
// （達成率が「答えた日だけを母数にする」のと同じ考え方で、記録が無い日と
// 未達の日を混ぜない）。
//
// 一覧を snapshots() で購読しないのは、この画面が開いている間に他タブから
// 書き換わらないため。常時開いている事件簿タブ（DiaryListPage）とは事情が違う。
class GoalLogPage extends StatefulWidget {
  final String uid;
  final Goal goal;

  const GoalLogPage({super.key, required this.uid, required this.goal});

  @override
  State<GoalLogPage> createState() => _GoalLogPageState();
}

class _GoalLogPageState extends State<GoalLogPage> {
  final FirestoreService _firestore = FirestoreService();

  bool _loading = true;
  bool _failed = false;
  // 新しい日が上。doc ID が 'YYYY-MM-DD' なので文字列の降順でよい
  List<MapEntry<String, Map<String, dynamic>>> _entries = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final entries = await _firestore.getGoalEntriesSince(
        widget.uid,
        widget.goal.id,
        // 着手日を持たない古い目標は全期間を見る（起点が分からないため）
        widget.goal.createdAt.isEmpty ? '' : widget.goal.createdAt,
      );
      if (!mounted) return;
      entries.sort((a, b) => b.key.compareTo(a.key));
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

  // 追跡した日数の分母。着手日が分かればその日から今日まで、分からなければ
  // 記録がある日数をそのまま使う（分母を作れないため）。
  int _trackedDays() {
    if (widget.goal.createdAt.isEmpty) return _entries.length;
    return daysSince(widget.goal.createdAt, DateTime.now()) + 1;
  }

  void _openDetail(String date, Map<String, dynamic> entry) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => GoalLogDetailPage(
          uid: widget.uid,
          goal: widget.goal,
          date: date,
          entry: entry,
        ),
      ),
    );
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
              '追跡記録',
              style: DetectiveTextStyles.appBarTitle(color: c.appBarFg),
            ),
            const SizedBox(height: 2),
            Text(
              '― 事件の経過 ―',
              style: DetectiveTextStyles.appBarSubtitle(
                color: c.appBarSubtitle,
              ),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: c.gold,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            _buildHeader(c),
            const SizedBox(height: 28),
            SectionLabel(
              '報告の記録',
              icon: Icons.fact_check_outlined,
              // 記録が無い日を行にしない代わりに、欠けを数で見せる
              trailing: _loading
                  ? null
                  : '記録 ${_entries.length} / ${_trackedDays()}日',
            ),
            const SizedBox(height: 12),

            if (_failed) ...[
              Text(
                '照会に失敗した。引き下げてもう一度試してくれ。',
                style: TextStyle(fontSize: 12, color: c.textSecondary),
              ),
              const SizedBox(height: 12),
            ],

            if (_loading)
              _NoticeCard(message: '照会中…')
            else if (_entries.isEmpty)
              _NoticeCard(message: 'まだ報告は上がっていない。')
            else
              for (final entry in _entries) ...[
                _GoalLogTile(
                  goal: widget.goal,
                  date: entry.key,
                  entry: entry.value,
                  onTap: () => _openDetail(entry.key, entry.value),
                ),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }

  // 何を追っている事件なのか。達成率のカードは出さない（分析室の仕事なので重ねない）。
  Widget _buildHeader(AppColors c) {
    final goal = widget.goal;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.flag_outlined, size: 14, color: c.gold),
              const SizedBox(width: 6),
              Text(
                elapsedLabel(goal, DateTime.now()),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: c.gold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            goal.title,
            style: DetectiveTextStyles.cardTitle(
              color: c.textPrimary,
            ).copyWith(fontSize: 15),
          ),
          if (goal.metric.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              goal.metric,
              style: TextStyle(
                fontSize: 12,
                color: c.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// 1日分の報告の行。日付と、質問ごとの答えをチップで並べる。
class _GoalLogTile extends StatelessWidget {
  final Goal goal;
  final String date;
  final Map<String, dynamic> entry;
  final VoidCallback onTap;

  const _GoalLogTile({
    required this.goal,
    required this.date,
    required this.entry,
    required this.onTap,
  });

  // 'YYYY-MM-DD' → '9月18日(水)'。解釈できない形式はそのまま出す。
  String _dateLabel() {
    final parts = date.split('-');
    if (parts.length != 3) return date;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return date;
    final weekday = _weekdayJa[DateTime(year, month, day).weekday - 1];
    return '$month月$day日($weekday)';
  }

  static const List<String> _weekdayJa = ['月', '火', '水', '木', '金', '土', '日'];

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
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: c.gold,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    bottomLeft: Radius.circular(4),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _dateLabel(),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: c.gold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final action in goal.actions)
                            _AnswerChip(
                              label: action.label,
                              value: _valueFor(action),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Icon(Icons.chevron_right, color: c.gold, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // その日の答え。数値項目は控えた数値（単位つき）、チェック項目は達成／未達。
  // 答えていない・スキップした項目は「—」（記録して0だったことと区別する）。
  String _valueFor(GoalAction action) {
    if (action.isNumeric) {
      final value = numericFor(entry, action.answerKey);
      if (value != null) {
        final text = value == value.roundToDouble()
            ? value.toStringAsFixed(0)
            : value.toStringAsFixed(1);
        return action.unit.isEmpty ? text : '$text${action.unit}';
      }
      // 数字として控えられなかった自由記述は、書かれたままを出す
      return answerFor(entry, action.answerKey) ?? '—';
    }
    return answerFor(entry, action.answerKey) ?? '—';
  }
}

// 質問名と答えの組。面には goldLight、その上の文字は caseNumberFg を使う
// （gold の塗りに載せる前景が onAccent、goldLight の面に載せる前景が caseNumberFg）。
class _AnswerChip extends StatelessWidget {
  final String label;
  final String value;

  const _AnswerChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.goldLight,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        '$label $value',
        style: TextStyle(
          fontSize: 11,
          color: c.caseNumberFg,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

// 読み込み中・記録が無いときに出す一言。
class _NoticeCard extends StatelessWidget {
  final String message;

  const _NoticeCard({required this.message});

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
