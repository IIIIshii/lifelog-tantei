import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../core/theme/detective_theme.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';

// 証拠分析室：活動記録をグラフで表示するページ
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
      final entries = await _firestore.getRecentEntries(uid, _days);

      final data = <String, double?>{};
      for (final entry in entries) {
        final numeric =
            entry.value['numericAnswers'] as Map<String, dynamic>?;
        final sleep = numeric?['sleep'];
        data[entry.key] = sleep != null ? (sleep as num).toDouble() : null;
      }

      setState(() {
        _sleepData.addAll(data);
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
    return Scaffold(
      backgroundColor: DetectiveTheme.background,
      appBar: AppBar(
        backgroundColor: DetectiveTheme.appBarBg,
        foregroundColor: const Color(0xFFE8DCC8),
        elevation: 0,
        toolbarHeight: 64,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('証拠分析室', style: DetectiveTheme.appBarTitle),
            const SizedBox(height: 2),
            const Text('― データを読む ―',
                style: DetectiveTheme.appBarSubtitle),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: DetectiveTheme.gold))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionHeader(title: '睡眠時間', subtitle: '直近$_days日間'),
                  const SizedBox(height: 16),
                  _SleepChart(dates: _dateRange, sleepData: _sleepData),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(title,
            style: DetectiveTheme.cardTitle.copyWith(fontSize: 18)),
        const SizedBox(width: 8),
        Text(subtitle,
            style: const TextStyle(
                fontSize: 12, color: DetectiveTheme.textSecondary)),
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
    final barGroups = <BarChartGroupData>[];
    for (var i = 0; i < dates.length; i++) {
      final hours = sleepData[dates[i]];
      barGroups.add(BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: hours ?? 0,
            color: hours != null
                ? DetectiveTheme.gold
                : DetectiveTheme.goldLight.withValues(alpha: 0.2),
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
        color: DetectiveTheme.cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DetectiveTheme.cardBorder),
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
              getDrawingHorizontalLine: (_) => FlLine(
                color: DetectiveTheme.cardBorder,
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
                  getTitlesWidget: (value, _) => Text(
                    '${value.toInt()}h',
                    style: const TextStyle(
                        fontSize: 10,
                        color: DetectiveTheme.textSecondary),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 30,
                  getTitlesWidget: (value, _) {
                    final i = value.toInt();
                    if (i < 0 || i >= dates.length) {
                      return const SizedBox.shrink();
                    }
                    // 2日おきにラベルを表示して詰まりを防ぐ
                    if (i % 2 != 0) return const SizedBox.shrink();
                    final parts = dates[i].split('-');
                    return Transform.rotate(
                      angle: -0.4,
                      child: Text(
                        '${parts[1]}/${parts[2]}',
                        style: const TextStyle(
                            fontSize: 9,
                            color: DetectiveTheme.textSecondary),
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
                getTooltipColor: (spot) => DetectiveTheme.appBarBg,
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  if (rod.toY == 0) return null;
                  final parts = dates[group.x].split('-');
                  final label = '${parts[1]}/${parts[2]}';
                  return BarTooltipItem(
                    '$label\n${rod.toY}h',
                    const TextStyle(
                        color: Color(0xFFE8DCC8), fontSize: 12),
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
