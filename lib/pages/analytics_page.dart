import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/detective_text_styles.dart';
import '../models/user_settings.dart';
import '../services/firestore_service.dart';
import '../services/gemini_service.dart';

// 証拠分析室：活動記録をグラフ・表で表示するページ
class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  final FirestoreService _firestore = FirestoreService();
  GeminiService? _gemini;

  bool _isLoading = true;
  bool _isGeneratingAnalysis = false;
  // YYYY-MM-DD → 睡眠時間（記録なし日はnull）
  final Map<String, double?> _sleepData = {};
  // YYYY-MM-DD → エントリ全データ
  final Map<String, Map<String, dynamic>> _entriesData = {};
  UserSettings? _settings;
  _AnalyticsSummary? _summary;
  String? _analysisText;
  DateTime? _analysisGeneratedAt;

  static const int _days = 14;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;

      // 並行フェッチ
      final entriesFuture = _firestore.getRecentEntries(uid, _days);
      final settingsFuture = _firestore.getUserSettings(uid);
      final analysisFuture = _firestore.getLatestAnalysis(uid);
      final entries = await entriesFuture;
      final settings = await settingsFuture;
      final analysis = await analysisFuture;

      final sleepData = <String, double?>{};
      final entriesData = <String, Map<String, dynamic>>{};
      for (final entry in entries) {
        entriesData[entry.key] = entry.value;
        final numeric =
            entry.value['numericAnswers'] as Map<String, dynamic>?;
        final sleep = numeric?['sleep'];
        sleepData[entry.key] = sleep != null ? (sleep as num).toDouble() : null;
      }

      final summary = _AnalyticsSummary.from(entries, _dateRange);

      _gemini = GeminiService(
        dotenv.env['GEMINI_API_KEY'] ?? '',
        settings.selectedRole,
      );

      setState(() {
        _sleepData.addAll(sleepData);
        _entriesData.addAll(entriesData);
        _settings = settings;
        _summary = summary;
        if (analysis != null) {
          _analysisText = analysis['text'] as String?;
          final ts = analysis['generatedAt'];
          if (ts is Timestamp) _analysisGeneratedAt = ts.toDate();
        }
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _generateAnalysis() async {
    if (_isGeneratingAnalysis) return;
    if (_entriesData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('まだ事件簿が記録されていない')),
      );
      return;
    }
    final gemini = _gemini;
    if (gemini == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('初期化が完了していない')),
      );
      return;
    }
    setState(() => _isGeneratingAnalysis = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final entries = _entriesData.entries
          .map((e) => MapEntry(e.key, e.value))
          .toList();
      final text = await gemini.generateAnalysis(entries);
      await _firestore.saveAnalysis(uid, text);
      if (!mounted) return;
      setState(() {
        _analysisText = text;
        _analysisGeneratedAt = DateTime.now();
        _isGeneratingAnalysis = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isGeneratingAnalysis = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('所見の生成に失敗した: $e')),
      );
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
                  _SectionHeader(title: '探偵の所見', subtitle: '直近$_days日間'),
                  const SizedBox(height: 16),
                  _AiInsightSection(
                    text: _analysisText,
                    generatedAt: _analysisGeneratedAt,
                    isLoading: _isGeneratingAnalysis,
                    onGenerate: _generateAnalysis,
                  ),
                  const SizedBox(height: 32),
                  _SectionHeader(title: 'サマリー', subtitle: '直近$_days日間'),
                  const SizedBox(height: 16),
                  _SummaryCards(summary: _summary),
                  const SizedBox(height: 32),
                  if (_summary != null &&
                      (_summary!.emotionDistribution.isNotEmpty ||
                          _summary!.placeDistribution.isNotEmpty)) ...[
                    _SectionHeader(title: '出来事の傾向', subtitle: '感情・場所の分布'),
                    const SizedBox(height: 16),
                    _DistributionCharts(summary: _summary!),
                    const SizedBox(height: 32),
                  ],
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

// ────────────────────────────────────────────────────────────
// 解析サマリー：エントリ群を集計した結果を保持する
// ────────────────────────────────────────────────────────────
class _AnalyticsSummary {
  final double? avgSleep; // 記録された日のみ平均
  final double? exerciseRate; // 0.0–1.0
  final double? studyRate; // 0.0–1.0
  final int streakDays; // 今日から遡る連続記録日数
  final int recordedDays; // 期間内で1件以上記録された日数
  final Map<String, int> emotionDistribution; // event_how 値別件数
  final Map<String, int> placeDistribution; // event_where 値別件数

  _AnalyticsSummary({
    required this.avgSleep,
    required this.exerciseRate,
    required this.studyRate,
    required this.streakDays,
    required this.recordedDays,
    required this.emotionDistribution,
    required this.placeDistribution,
  });

  factory _AnalyticsSummary.from(
    List<MapEntry<String, Map<String, dynamic>>> entries,
    List<String> dateRange,
  ) {
    final dateSet = dateRange.toSet();
    final relevant = entries.where((e) => dateSet.contains(e.key)).toList();

    final sleeps = <double>[];
    int exerciseDone = 0, exerciseRecorded = 0;
    int studyDone = 0, studyRecorded = 0;
    final emotion = <String, int>{};
    final place = <String, int>{};

    for (final e in relevant) {
      final numeric = e.value['numericAnswers'] as Map<String, dynamic>?;
      final answers = e.value['answers'] as Map<String, dynamic>?;
      final sleep = numeric?['sleep'];
      if (sleep is num) sleeps.add(sleep.toDouble());

      final ex = answers?['exercise'] as String?;
      if (ex != null && ex.isNotEmpty) {
        exerciseRecorded++;
        if (ex == 'した') exerciseDone++;
      }
      final st = answers?['study'] as String?;
      if (st != null && st.isNotEmpty) {
        studyRecorded++;
        if (st == 'した') studyDone++;
      }
      final how = answers?['event_how'] as String?;
      if (how is String && how.isNotEmpty) {
        emotion[how] = (emotion[how] ?? 0) + 1;
      }
      final where = answers?['event_where'] as String?;
      if (where is String && where.isNotEmpty) {
        place[where] = (place[where] ?? 0) + 1;
      }
    }

    // 今日から遡って連続して記録があった日数
    final recordedSet = {for (final e in relevant) e.key};
    int streak = 0;
    for (int i = dateRange.length - 1; i >= 0; i--) {
      if (recordedSet.contains(dateRange[i])) {
        streak++;
      } else {
        break;
      }
    }

    return _AnalyticsSummary(
      avgSleep: sleeps.isEmpty
          ? null
          : sleeps.reduce((a, b) => a + b) / sleeps.length,
      exerciseRate:
          exerciseRecorded == 0 ? null : exerciseDone / exerciseRecorded,
      studyRate: studyRecorded == 0 ? null : studyDone / studyRecorded,
      streakDays: streak,
      recordedDays: recordedSet.length,
      emotionDistribution: emotion,
      placeDistribution: place,
    );
  }
}

// ────────────────────────────────────────────────────────────
// サマリーカード：平均睡眠・運動実施率・勉強実施率・連続記録
// ────────────────────────────────────────────────────────────
class _SummaryCards extends StatelessWidget {
  final _AnalyticsSummary? summary;
  const _SummaryCards({required this.summary});

  @override
  Widget build(BuildContext context) {
    final s = summary;
    if (s == null || s.recordedDays == 0) {
      return _EmptyCard(message: 'まだ記録が足りない');
    }

    final cards = <Widget>[
      _StatCard(
        label: '平均睡眠',
        value: s.avgSleep == null
            ? '—'
            : '${s.avgSleep!.toStringAsFixed(1)}h',
      ),
      _StatCard(
        label: '運動実施率',
        value: s.exerciseRate == null
            ? '—'
            : '${(s.exerciseRate! * 100).round()}%',
      ),
      _StatCard(
        label: '勉強実施率',
        value: s.studyRate == null
            ? '—'
            : '${(s.studyRate! * 100).round()}%',
      ),
      _StatCard(
        label: '連続記録',
        value: '${s.streakDays}日',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // 横幅に応じてカード幅を調整（最低160）
        final spacing = 12.0;
        final available = constraints.maxWidth;
        // 4列入るならそれ、入らないなら2列
        final cardWidth = available >= 4 * 160 + 3 * spacing
            ? (available - 3 * spacing) / 4
            : (available - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: cards
              .map((w) => SizedBox(width: cardWidth, child: w))
              .toList(),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 11, color: c.textSecondary)),
          const SizedBox(height: 6),
          Text(
            value,
            style: DetectiveTextStyles.cardTitle(color: c.gold)
                .copyWith(fontSize: 22),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// 分布パイチャート：感情・場所の分布を並べる
// ────────────────────────────────────────────────────────────
class _DistributionCharts extends StatelessWidget {
  final _AnalyticsSummary summary;
  const _DistributionCharts({required this.summary});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 520;
        final emotionChart = _PieCard(
          title: '感情',
          distribution: summary.emotionDistribution,
        );
        final placeChart = _PieCard(
          title: '場所',
          distribution: summary.placeDistribution,
        );
        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: emotionChart),
              const SizedBox(width: 12),
              Expanded(child: placeChart),
            ],
          );
        }
        return Column(
          children: [
            emotionChart,
            const SizedBox(height: 12),
            placeChart,
          ],
        );
      },
    );
  }
}

class _PieCard extends StatelessWidget {
  final String title;
  final Map<String, int> distribution;
  const _PieCard({required this.title, required this.distribution});

  static const _palette = <Color>[
    Color(0xFFC8A951),
    Color(0xFF8B6F2E),
    Color(0xFFD4B97D),
    Color(0xFF6B5320),
    Color(0xFFE7D6A8),
    Color(0xFFA0824A),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (distribution.isEmpty) {
      return _EmptyCard(message: '$title の記録なし');
    }
    final total = distribution.values.fold<int>(0, (a, b) => a + b);
    final sortedEntries = distribution.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final sections = <PieChartSectionData>[];
    for (var i = 0; i < sortedEntries.length; i++) {
      final e = sortedEntries[i];
      final color = _palette[i % _palette.length];
      sections.add(PieChartSectionData(
        value: e.value.toDouble(),
        color: color,
        title: '${(e.value / total * 100).round()}%',
        titleStyle: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.white),
        radius: 52,
      ));
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: DetectiveTextStyles.cardTitle(color: c.textPrimary)
                  .copyWith(fontSize: 14)),
          const SizedBox(height: 8),
          SizedBox(
            height: 140,
            child: PieChart(
              PieChartData(
                sections: sections,
                centerSpaceRadius: 22,
                sectionsSpace: 2,
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 凡例
          ...sortedEntries.asMap().entries.map((e) {
            final color = _palette[e.key % _palette.length];
            final label = e.value.key;
            final count = e.value.value;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      style:
                          TextStyle(fontSize: 11, color: c.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text('$count',
                      style: TextStyle(
                          fontSize: 11, color: c.textSecondary)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// AI所見セクション：探偵の推理結果カード
// ────────────────────────────────────────────────────────────
class _AiInsightSection extends StatelessWidget {
  final String? text;
  final DateTime? generatedAt;
  final bool isLoading;
  final VoidCallback onGenerate;

  const _AiInsightSection({
    required this.text,
    required this.generatedAt,
    required this.isLoading,
    required this.onGenerate,
  });

  String _formatTimestamp(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}/${two(dt.month)}/${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasText = text != null && text!.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isLoading) ...[
            Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: c.gold),
                ),
                const SizedBox(width: 10),
                Text('探偵が記録を読み返している…',
                    style: TextStyle(
                        fontSize: 13, color: c.textSecondary)),
              ],
            ),
          ] else if (hasText) ...[
            Text(
              text!,
              style: TextStyle(
                  fontSize: 13, color: c.textPrimary, height: 1.6),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (generatedAt != null)
                  Text(
                    '記録: ${_formatTimestamp(generatedAt!)}',
                    style:
                        TextStyle(fontSize: 10, color: c.textSecondary),
                  )
                else
                  const SizedBox.shrink(),
                TextButton.icon(
                  onPressed: onGenerate,
                  icon: Icon(Icons.refresh, size: 16, color: c.gold),
                  label: Text('再推理',
                      style: TextStyle(color: c.gold, fontSize: 12)),
                ),
              ],
            ),
          ] else ...[
            Text(
              'まだ所見は記録されていない。',
              style: TextStyle(fontSize: 13, color: c.textSecondary),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: onGenerate,
                icon: const Icon(Icons.search, size: 16),
                label: const Text('探偵に推理させる'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.gold,
                  foregroundColor: c.appBarFg,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// 空状態の小カード
class _EmptyCard extends StatelessWidget {
  final String message;
  const _EmptyCard({required this.message});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.cardBorder),
      ),
      child: Text(message,
          style: TextStyle(fontSize: 12, color: c.textSecondary)),
    );
  }
}
