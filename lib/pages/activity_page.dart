import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/user_settings.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';

class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key});

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _history = [];
  UserSettings _settings = UserSettings.defaults();
  final AuthService _auth = AuthService();
  final FirestoreService _firestore = FirestoreService();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = await _auth.signInAnonymously();
    if (uid == null) {
      setState(() => _isLoading = false);
      return;
    }
    final results = await Future.wait([
      _firestore.getStatsHistory(uid),
      _firestore.getUserSettings(uid),
    ]);
    setState(() {
      _history = results[0] as List<Map<String, dynamic>>;
      _settings = results[1] as UserSettings;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('活動の記録'),
        backgroundColor: const Color(0xFF2E4A5C),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF5F0EB),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
              ? const Center(
                  child: Text(
                    '日記を書くとここにグラフが表示されます',
                    style: TextStyle(color: Color(0xFF7A5C4A)),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _DiaryCountCard(history: _history),
                    if (_settings.recordSleep) ...[
                      const SizedBox(height: 16),
                      _SleepChart(history: _history),
                    ],
                    if (_settings.recordExercise) ...[
                      const SizedBox(height: 16),
                      _BoolChart(
                        history: _history,
                        field: 'exercise',
                        title: '運動の記録',
                        color: const Color(0xFF2E5C45),
                      ),
                    ],
                    if (_settings.recordStudy) ...[
                      const SizedBox(height: 16),
                      _StudyList(history: _history),
                    ],
                    if (_settings.recordFood) ...[
                      const SizedBox(height: 16),
                      _FoodList(history: _history),
                    ],
                  ],
                ),
    );
  }
}

// ────────────────────────────────────────────
// 日記記録日数カード
// ────────────────────────────────────────────
class _DiaryCountCard extends StatelessWidget {
  final List<Map<String, dynamic>> history;
  const _DiaryCountCard({required this.history});

  @override
  Widget build(BuildContext context) {
    final count = history.where((e) => e['diary'] != null).length;
    return _ChartCard(
      title: '日記の記録数',
      child: Center(
        child: RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: '$count',
                style: const TextStyle(
                  fontSize: 56,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF5C3D2E),
                ),
              ),
              const TextSpan(
                text: ' 日',
                style: TextStyle(fontSize: 20, color: Color(0xFF7A5C4A)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────
// 睡眠時間グラフ
// ────────────────────────────────────────────
class _SleepChart extends StatelessWidget {
  final List<Map<String, dynamic>> history;
  const _SleepChart({required this.history});

  @override
  Widget build(BuildContext context) {
    final data = history
        .where((e) => e['stats']?['sleep'] != null)
        .toList();

    if (data.isEmpty) {
      return _ChartCard(
        title: '睡眠時間',
        child: const _NoData(),
      );
    }

    final spots = data.asMap().entries.map((e) {
      final sleep = (e.value['stats']['sleep'] as num).toDouble();
      return FlSpot(e.key.toDouble(), sleep);
    }).toList();

    final labels = data.map((e) {
      final date = e['date'] as String;
      return date.substring(5); // MM-DD
    }).toList();

    return _ChartCard(
      title: '睡眠時間（時間）',
      child: SizedBox(
        height: 180,
        child: LineChart(
          LineChartData(
            minY: 0,
            maxY: 12,
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: 3,
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: 3,
                  reservedSize: 28,
                  getTitlesWidget: (v, _) => Text(
                    '${v.toInt()}h',
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 20,
                  getTitlesWidget: (v, _) {
                    final i = v.toInt();
                    if (i < 0 || i >= labels.length) return const SizedBox();
                    return Text(
                      labels[i],
                      style:
                          const TextStyle(fontSize: 9, color: Colors.grey),
                    );
                  },
                ),
              ),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                color: const Color(0xFF2E4A5C),
                barWidth: 2.5,
                dotData: const FlDotData(show: true),
                belowBarData: BarAreaData(
                  show: true,
                  color: const Color(0xFF2E4A5C).withValues(alpha: 0.12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────
// 運動などの ON/OFF 棒グラフ
// ────────────────────────────────────────────
class _BoolChart extends StatelessWidget {
  final List<Map<String, dynamic>> history;
  final String field;
  final String title;
  final Color color;

  const _BoolChart({
    required this.history,
    required this.field,
    required this.title,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final data = history
        .where((e) => e['stats']?[field] != null)
        .toList();

    if (data.isEmpty) {
      return _ChartCard(title: title, child: const _NoData());
    }

    final labels = data.map((e) {
      final date = e['date'] as String;
      return date.substring(5);
    }).toList();

    final bars = data.asMap().entries.map((e) {
      final val = e.value['stats'][field] == true ? 1.0 : 0.0;
      return BarChartGroupData(
        x: e.key,
        barRods: [
          BarChartRodData(
            toY: val,
            color: val == 1 ? color : Colors.grey.shade200,
            width: 14,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      );
    }).toList();

    return _ChartCard(
      title: title,
      child: SizedBox(
        height: 140,
        child: BarChart(
          BarChartData(
            maxY: 1.2,
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 20,
                  getTitlesWidget: (v, _) {
                    final i = v.toInt();
                    if (i < 0 || i >= labels.length) return const SizedBox();
                    return Text(
                      labels[i],
                      style:
                          const TextStyle(fontSize: 9, color: Colors.grey),
                    );
                  },
                ),
              ),
              leftTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            barGroups: bars,
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────
// 勉強内容リスト
// ────────────────────────────────────────────
class _StudyList extends StatelessWidget {
  final List<Map<String, dynamic>> history;
  const _StudyList({required this.history});

  @override
  Widget build(BuildContext context) {
    final entries = history
        .where((e) => e['stats']?['study'] != null)
        .map((e) => (date: e['date'] as String, text: e['stats']['study'] as String))
        .toList()
        .reversed
        .toList();

    if (entries.isEmpty) {
      return _ChartCard(title: '勉強の記録', child: const _NoData());
    }

    return _ChartCard(
      title: '勉強の記録',
      child: Column(
        children: entries.map((e) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.date.substring(5),
                  style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      fontFeatures: []),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(e.text,
                      style: const TextStyle(fontSize: 14)),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ────────────────────────────────────────────
// 食事リスト
// ────────────────────────────────────────────
class _FoodList extends StatelessWidget {
  final List<Map<String, dynamic>> history;
  const _FoodList({required this.history});

  @override
  Widget build(BuildContext context) {
    final entries = history
        .where((e) {
          final food = e['stats']?['food'];
          return food != null && (food as List).isNotEmpty;
        })
        .map((e) => (
              date: e['date'] as String,
              foods: (e['stats']['food'] as List).cast<String>(),
            ))
        .toList()
        .reversed
        .toList();

    if (entries.isEmpty) {
      return _ChartCard(title: '食事の記録', child: const _NoData());
    }

    return _ChartCard(
      title: '食事の記録',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: entries.map((e) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.date.substring(5),
                  style:
                      const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: e.foods
                        .map((f) => Chip(
                              label: Text(f,
                                  style: const TextStyle(fontSize: 12)),
                              padding: EdgeInsets.zero,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ))
                        .toList(),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ────────────────────────────────────────────
// 共通カードラッパー
// ────────────────────────────────────────────
class _ChartCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _ChartCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Color(0xFF7A5C4A),
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _NoData extends StatelessWidget {
  const _NoData();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'まだデータがありません',
          style: TextStyle(fontSize: 13, color: Colors.grey),
        ),
      ),
    );
  }
}
