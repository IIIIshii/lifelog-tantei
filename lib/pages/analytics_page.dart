import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/detective_text_styles.dart';
import '../models/user_settings.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';

// 証拠分析室：活動記録をグラフ・表で表示するページ
class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  final AuthService _auth = AuthService();
  final FirestoreService _firestore = FirestoreService();

  bool _isLoading = true;
  // YYYY-MM-DD → 睡眠時間（記録なし日はnull）
  final Map<String, double?> _sleepData = {};
  // YYYY-MM-DD → エントリ全データ
  final Map<String, Map<String, dynamic>> _entriesData = {};
  UserSettings? _settings;

  static const int _days = 14;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final uid = await _auth.signInAnonymously();
      if (uid == null) {
        setState(() => _isLoading = false);
        return;
      }

      // 並行フェッチ
      final entriesFuture = _firestore.getRecentEntries(uid, _days);
      final settingsFuture = _firestore.getUserSettings(uid);
      final entries = await entriesFuture;
      final settings = await settingsFuture;

      final sleepData = <String, double?>{};
      final entriesData = <String, Map<String, dynamic>>{};
      for (final entry in entries) {
        entriesData[entry.key] = entry.value;
        final numeric =
            entry.value['numericAnswers'] as Map<String, dynamic>?;
        final sleep = numeric?['sleep'];
        sleepData[entry.key] = sleep != null ? (sleep as num).toDouble() : null;
      }

      setState(() {
        _sleepData.addAll(sleepData);
        _entriesData.addAll(entriesData);
        _settings = settings;
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  // 直近 _days 日分の YYYY-MM-DD リスト（古い順）
  List<String> get _dateRange {
    final now = DateTime.now();
    return List.generate(_days, (i) {
      final d = now.subtract(Duration(days: _days - 1 - i));
      return d.toIso8601String().split('T')[0];
    });
  }

  @override
  Widget build(BuildContext context) {
    final dates = _dateRange;
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
            Text('証拠分析室',
                style: DetectiveTextStyles.appBarTitle(color: c.appBarFg)),
            const SizedBox(height: 2),
            Text('― データを読む ―',
                style: DetectiveTextStyles.appBarSubtitle(
                    color: c.appBarSubtitle)),
          ],
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: c.gold))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionHeader(title: '睡眠時間', subtitle: '直近$_days日間'),
                  const SizedBox(height: 16),
                  _SleepChart(dates: dates, sleepData: _sleepData),
                  const SizedBox(height: 32),
                  _SectionHeader(title: '活動記録', subtitle: '直近$_days日間'),
                  const SizedBox(height: 16),
                  _RecordsTable(
                    dates: dates.reversed.toList(), // 新しい順
                    entriesData: _entriesData,
                    customQuestions: _settings?.customQuestions ?? [],
                  ),
                ],
              ),
            ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// セクションヘッダー
// ────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(title,
            style: DetectiveTextStyles.cardTitle(color: c.textPrimary)
                .copyWith(fontSize: 18)),
        const SizedBox(width: 8),
        Text(subtitle,
            style: TextStyle(fontSize: 12, color: c.textSecondary)),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────
// 睡眠時間バーチャート
// ────────────────────────────────────────────────────────────
class _SleepChart extends StatelessWidget {
  final List<String> dates;
  final Map<String, double?> sleepData;

  const _SleepChart({required this.dates, required this.sleepData});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final barGroups = <BarChartGroupData>[];
    for (var i = 0; i < dates.length; i++) {
      final hours = sleepData[dates[i]];
      barGroups.add(BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: hours ?? 0,
            color: hours != null
                ? c.gold
                : c.goldLight.withValues(alpha: 0.2),
            width: 14,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ],
      ));
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(4, 20, 16, 12),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.cardBorder),
      ),
      child: SizedBox(
        height: 220,
        child: BarChart(
          BarChartData(
            maxY: 12,
            minY: 0,
            barGroups: barGroups,
            gridData: FlGridData(
              show: true,
              horizontalInterval: 2,
              getDrawingHorizontalLine: (value) => FlLine(
                color: c.cardBorder,
                strokeWidth: 1,
              ),
              drawVerticalLine: false,
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: 2,
                  reservedSize: 32,
                  getTitlesWidget: (value, meta) => Text(
                    '${value.toInt()}h',
                    style: TextStyle(fontSize: 10, color: c.textSecondary),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 30,
                  getTitlesWidget: (value, meta) {
                    final i = value.toInt();
                    if (i < 0 || i >= dates.length) {
                      return const SizedBox.shrink();
                    }
                    if (i % 2 != 0) return const SizedBox.shrink();
                    final parts = dates[i].split('-');
                    return Transform.rotate(
                      angle: -0.4,
                      child: Text(
                        '${parts[1]}/${parts[2]}',
                        style:
                            TextStyle(fontSize: 9, color: c.textSecondary),
                      ),
                    );
                  },
                ),
              ),
              topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (spot) => c.appBarBg,
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  if (rod.toY == 0) return null;
                  final parts = dates[group.x].split('-');
                  final label = '${parts[1]}/${parts[2]}';
                  return BarTooltipItem(
                    '$label\n${rod.toY}h',
                    TextStyle(color: c.appBarFg, fontSize: 12),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// 活動記録テーブル（食事・運動・勉強・カスタム質問）
// ────────────────────────────────────────────────────────────
class _RecordsTable extends StatelessWidget {
  // dates は新しい順（降順）
  final List<String> dates;
  final Map<String, Map<String, dynamic>> entriesData;
  final List<String> customQuestions;

  const _RecordsTable({
    required this.dates,
    required this.entriesData,
    required this.customQuestions,
  });

  static const _fixedHeaders = ['日付', '食事', '運動', '勉強'];
  static const _fixedKeys = ['food', 'exercise', 'study'];

  // カスタム質問ラベルを最大10文字に切り詰める
  String _truncate(String s, int max) =>
      s.length > max ? '${s.substring(0, max)}…' : s;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final customHeaders = customQuestions
        .asMap()
        .entries
        .map((e) => _truncate(e.value, 10))
        .toList();
    final allHeaders = [..._fixedHeaders, ...customHeaders];

    return Container(
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.cardBorder),
      ),
      clipBehavior: Clip.hardEdge,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 20,
          headingRowHeight: 38,
          dataRowMinHeight: 36,
          dataRowMaxHeight: 52,
          headingRowColor:
              WidgetStateProperty.all(c.gold.withValues(alpha: 0.12)),
          headingTextStyle: TextStyle(
            color: c.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
          dataTextStyle: TextStyle(
            color: c.textSecondary,
            fontSize: 12,
          ),
          dividerThickness: 0.5,
          columns: allHeaders
              .map((h) => DataColumn(label: Text(h)))
              .toList(),
          rows: dates.map((date) {
            final answers = entriesData[date]?['answers']
                as Map<String, dynamic>?;
            final parts = date.split('-');
            final dateLabel = '${parts[1]}/${parts[2]}';

            final fixedCells = [
              DataCell(Text(dateLabel,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                      fontSize: 12))),
              ..._fixedKeys.map((key) {
                final val = answers?[key] as String?;
                return DataCell(_TableCell(value: val));
              }),
            ];

            final customCells = customQuestions
                .asMap()
                .entries
                .map((e) {
              final val = answers?['custom_${e.key}'] as String?;
              return DataCell(_TableCell(value: val));
            }).toList();

            return DataRow(cells: [...fixedCells, ...customCells]);
          }).toList(),
        ),
      ),
    );
  }
}

// テーブルのセル内テキスト（値なしのとき「—」を薄く表示）
class _TableCell extends StatelessWidget {
  final String? value;
  const _TableCell({required this.value});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (value == null) {
      return Text('—',
          style: TextStyle(color: c.cardBorder, fontSize: 12));
    }
    return Text(
      value!,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: c.textSecondary, fontSize: 12),
    );
  }
}
