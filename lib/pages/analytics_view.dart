import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../core/chart_scale.dart';
import '../core/daily_record.dart';
import '../core/goal_progress.dart';
import '../core/streak.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/detective_text_styles.dart';
import '../models/goal.dart';
import '../models/record_field.dart';
import '../services/firestore_service.dart';
import '../services/gemini_service.dart';

// 証拠分析室：日々の記録と日記をグラフ・表・AIの所見で読み返す。
//
// 事件簿タブ（CaseFilesPage）の「分析」側の中身。AppBar はタブ側が持つので、
// ここは本文だけを返す。この画面が自分で持つデータは AI の所見（analyses）だけで、
// 他は records / diaries / 記録の型 / 目標を読むだけ。
class AnalyticsView extends StatefulWidget {
  final String uid;

  /// MainShell が値を進めるたびに読み直すシグナル。
  /// タブは IndexedStack で保持され破棄されないため、記録を書き足しても
  /// この合図が無いとグラフが古いまま残る。
  final ValueListenable<int> refreshSignal;

  const AnalyticsView({
    super.key,
    required this.uid,
    required this.refreshSignal,
  });

  @override
  State<AnalyticsView> createState() => _AnalyticsViewState();
}

class _AnalyticsViewState extends State<AnalyticsView>
    with AutomaticKeepAliveClientMixin {
  final FirestoreService _firestore = FirestoreService();
  GeminiService? _gemini;

  static const int _days = 14;

  bool _isLoading = true;
  bool _isGeneratingAnalysis = false;
  bool _isGeneratingDailyAnalysis = false;

  List<MapEntry<String, Map<String, dynamic>>> _records = const [];
  List<MapEntry<String, Map<String, dynamic>>> _diaries = const [];
  List<RecordField> _fields = const [];
  List<Goal> _goals = const [];
  // 値のキー → 記録項目。記録には項目 id しか入っていないので、
  // これを添えないとカスタム項目・目標の値は所見の材料から落ちる。
  Map<String, RecordField> _fieldIndex = const {};
  _AnalyticsSummary? _summary;
  String? _analysisText;
  String? _dailyAnalysisText;
  DateTime? _analysisGeneratedAt;
  DateTime? _dailyAnalysisGeneratedAt;

  // タブを横に切り替えても読み直さない（読み直しは refreshSignal と引き下げで行う）
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.refreshSignal.addListener(_loadData);
    _loadData();
  }

  @override
  void dispose() {
    widget.refreshSignal.removeListener(_loadData);
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final uid = widget.uid;
      final recordsFuture = _firestore.getRecentRecords(uid, _days);
      final diariesFuture = _firestore.getRecentDiaries(uid, _days);
      final fieldsFuture = _firestore.getFields(uid);
      final goalsFuture = _firestore.getGoals(uid);
      final settingsFuture = _firestore.getUserSettings(uid);
      final analysisFuture = _firestore.getLatestAnalysis(uid);
      final dailyCommentFuture = _firestore.getTodayComment(uid);
      final selfAnalysisFuture = _firestore.getSelfAnalysis(uid);
      final records = await recordsFuture;
      final diaries = await diariesFuture;
      final fields = await fieldsFuture;
      final goals = await goalsFuture;
      final settings = await settingsFuture;
      final analysis = await analysisFuture;
      final dailyComment = await dailyCommentFuture;
      final selfAnalysis = await selfAnalysisFuture;

      // 自己分析は共有トグルの判定ごと GeminiService に委ねる。
      // OFF なら所見・今日のコメントのどちらにも差し込まれない。
      _gemini = GeminiService(
        dotenv.env['GEMINI_API_KEY'] ?? '',
        settings.selectedRole,
        selfAnalysis: selfAnalysis,
      );

      if (!mounted) return;
      setState(() {
        _records = records;
        _diaries = diaries;
        _fields = fields;
        _goals = goals;
        _fieldIndex = fieldIndex(fields, goals);
        _summary = _AnalyticsSummary.from(records, diaries, _dateRange);
        if (analysis != null) {
          _analysisText = analysis['text'] as String?;
          final ts = analysis['generatedAt'];
          if (ts is Timestamp) _analysisGeneratedAt = ts.toDate();
        }
        _dailyAnalysisText = null;
        _dailyAnalysisGeneratedAt = null;
        if (dailyComment != null) {
          final ts = dailyComment['generatedAt'];
          // 日付が変わっていれば古いキャッシュなので表示しない
          if (ts is Timestamp && dateKey(ts.toDate()) == dateKey(DateTime.now())) {
            _dailyAnalysisText = dailyComment['text'] as String?;
            _dailyAnalysisGeneratedAt = ts.toDate();
          }
        }
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  // AI へ渡す日々。記録と日記を日付で重ねたもの（保存はしない）。
  List<MapEntry<String, Map<String, dynamic>>> get _mergedDays =>
      mergeDays(_records, _diaries);

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _generateAnalysis() async {
    if (_isGeneratingAnalysis) return;
    final days = _mergedDays;
    if (days.isEmpty) {
      _snack('まだ記録が残されていない');
      return;
    }
    final gemini = _gemini;
    if (gemini == null) {
      _snack('初期化が完了していない');
      return;
    }
    setState(() => _isGeneratingAnalysis = true);
    try {
      final text = await gemini.generateAnalysis(days, fields: _fieldIndex);
      await _firestore.saveAnalysis(widget.uid, text);
      if (!mounted) return;
      setState(() {
        _analysisText = text;
        _analysisGeneratedAt = DateTime.now();
        _isGeneratingAnalysis = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isGeneratingAnalysis = false);
      _snack('所見の生成に失敗した: $e');
    }
  }

  Future<void> _generateDailyAnalysis() async {
    if (_isGeneratingDailyAnalysis) return;
    final days = _mergedDays;
    final todayKey = dateKey(DateTime.now());
    final today = days
        .firstWhere(
          (entry) => entry.key == todayKey,
          orElse: () => MapEntry(todayKey, const <String, dynamic>{}),
        )
        .value;
    if (today.isEmpty) {
      _snack('今日の記録がまだない');
      return;
    }
    final gemini = _gemini;
    if (gemini == null) {
      _snack('初期化が完了していない');
      return;
    }
    setState(() => _isGeneratingDailyAnalysis = true);
    try {
      final text = await gemini.generateDailyComment(
        today,
        days,
        fields: _fieldIndex,
      );
      await _firestore.saveTodayComment(widget.uid, text);
      if (!mounted) return;
      setState(() {
        _dailyAnalysisText = text;
        _dailyAnalysisGeneratedAt = DateTime.now();
        _isGeneratingDailyAnalysis = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isGeneratingDailyAnalysis = false);
      _snack('コメントの生成に失敗した: $e');
    }
  }

  // 直近 _days 日分の YYYY-MM-DD リスト（古い順）。
  // Duration で引かずに日フィールドで遡るのは夏時間対策（streak.dart と同じ）。
  List<String> get _dateRange {
    final now = DateTime.now();
    return List.generate(
      _days,
      (i) => dateKey(DateTime(now.year, now.month, now.day - (_days - 1 - i))),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final c = context.colors;
    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: c.gold));
    }

    final dates = _dateRange;
    final recordByDate = {for (final e in _records) e.key: e.value};
    final sleepActive = _fields.any((f) => f.id == kSleepFieldId && f.active);
    // 睡眠以外の数値項目は、点が2つ以上あるものだけ推移を出す
    final numericFields = [
      for (final field in _fields)
        if (field.active &&
            field.kind == FieldKind.numeric &&
            field.id != kSleepFieldId &&
            numericSeries(_records, field.id).length >= 2)
          field,
    ];
    final tableFields = _fields.where((f) => f.active).toList();

    return RefreshIndicator(
      color: c.gold,
      backgroundColor: c.cardBg,
      onRefresh: _loadData,
      child: SingleChildScrollView(
        // 中身が画面に収まっているときも引っ張って更新できるようにする
        physics: const AlwaysScrollableScrollPhysics(),
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
            _SectionHeader(title: '今日の行動', subtitle: '本日分'),
            const SizedBox(height: 16),
            _AiInsightSection(
              text: _dailyAnalysisText,
              generatedAt: _dailyAnalysisGeneratedAt,
              isLoading: _isGeneratingDailyAnalysis,
              onGenerate: _generateDailyAnalysis,
            ),
            const SizedBox(height: 32),
            _SectionHeader(title: 'サマリー', subtitle: '直近$_days日間'),
            const SizedBox(height: 16),
            _SummaryCards(summary: _summary),
            const SizedBox(height: 32),
            // 目標を追っていないときはセクションごと消える
            if (_goals.isNotEmpty) ...[
              _SectionHeader(
                title: '追跡中の目標',
                subtitle: '${_goals.length}件 / 直近$_days日間',
              ),
              const SizedBox(height: 16),
              // 見出しは1つに留め、目標ごとの区切りは罫線で表す。
              for (var i = 0; i < _goals.length; i++) ...[
                if (i > 0) ...[
                  const SizedBox(height: 24),
                  Divider(height: 1, color: c.cardBorder),
                  const SizedBox(height: 24),
                ],
                _GoalProgressSection(goal: _goals[i], records: _records),
              ],
              const SizedBox(height: 32),
            ],
            if (_summary != null && _summary!.moodDistribution.isNotEmpty) ...[
              _SectionHeader(title: '気分の傾向', subtitle: '今日の気分の分布'),
              const SizedBox(height: 16),
              _PieCard(title: '今日の気分', distribution: _summary!.moodDistribution),
              const SizedBox(height: 32),
            ],
            if (sleepActive) ...[
              _SectionHeader(title: '睡眠時間', subtitle: '直近$_days日間'),
              const SizedBox(height: 16),
              _SleepChart(
                dates: dates,
                sleepData: {
                  for (final date in dates)
                    date: numberOf(recordByDate[date], kSleepFieldId),
                },
              ),
              const SizedBox(height: 32),
            ],
            if (numericFields.isNotEmpty) ...[
              _SectionHeader(title: '数値の推移', subtitle: '直近$_days日間'),
              const SizedBox(height: 16),
              for (final field in numericFields) ...[
                _NumericChart(
                  label: field.label,
                  unit: field.unit,
                  target: field.target,
                  series: numericSeries(_records, field.id),
                ),
                const SizedBox(height: 16),
              ],
              const SizedBox(height: 16),
            ],
            _SectionHeader(title: '記録の一覧', subtitle: '直近$_days日間'),
            const SizedBox(height: 16),
            _RecordsTable(
              dates: dates.reversed.toList(), // 新しい順
              recordByDate: recordByDate,
              fields: tableFields,
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
        Text(
          title,
          style: DetectiveTextStyles.cardTitle(
            color: c.textPrimary,
          ).copyWith(fontSize: 18),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            subtitle,
            style: TextStyle(fontSize: 12, color: c.textSecondary),
          ),
        ),
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
      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: hours ?? 0,
              // 記録なしの日も「棒がそこにある」ことは伝えたいので、
              // 薄い透過ではなく cardBorder を不透明で使う。
              // グラフの意味ある部分は背景に対し 3:1 が要る（WCAG SC 1.4.11）。
              color: hours != null ? c.gold : c.cardBorder,
              width: 14,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(4),
              ),
            ),
          ],
        ),
      );
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
              getDrawingHorizontalLine: (value) =>
                  FlLine(color: c.cardBorder, strokeWidth: 1),
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
                    return Transform.rotate(
                      angle: -0.4,
                      child: Text(
                        _shortDate(dates[i]),
                        style: TextStyle(fontSize: 9, color: c.textSecondary),
                      ),
                    );
                  },
                ),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (spot) => c.appBarBg,
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  if (rod.toY == 0) return null;
                  return BarTooltipItem(
                    '${_shortDate(dates[group.x])}\n${rod.toY}h',
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

// 'YYYY-MM-DD' → 'MM/DD'
String _shortDate(String key) {
  final parts = key.split('-');
  return parts.length == 3 ? '${parts[1]}/${parts[2]}' : key;
}

// ────────────────────────────────────────────────────────────
// 記録の一覧（行＝日付、列＝使っている記録項目）
// ────────────────────────────────────────────────────────────
class _RecordsTable extends StatelessWidget {
  // dates は新しい順（降順）
  final List<String> dates;
  final Map<String, Map<String, dynamic>> recordByDate;
  final List<RecordField> fields;

  const _RecordsTable({
    required this.dates,
    required this.recordByDate,
    required this.fields,
  });

  // 見出しを最大10文字に切り詰める
  String _truncate(String s, int max) =>
      s.length > max ? '${s.substring(0, max)}…' : s;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (fields.isEmpty) {
      return const _EmptyCard(message: '記録する項目が設定されていない');
    }

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
          headingRowColor: WidgetStateProperty.all(
            c.gold.withValues(alpha: 0.12),
          ),
          headingTextStyle: TextStyle(
            color: c.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
          dataTextStyle: TextStyle(color: c.textSecondary, fontSize: 12),
          dividerThickness: 0.5,
          columns: [
            const DataColumn(label: Text('日付')),
            for (final field in fields)
              DataColumn(label: Text(_truncate(field.label, 10))),
          ],
          rows: [
            for (final date in dates)
              DataRow(
                cells: [
                  DataCell(
                    Text(
                      _shortDate(date),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  for (final field in fields)
                    DataCell(
                      _TableCell(
                        value: formatValue(
                          field,
                          valueOf(recordByDate[date], field.id),
                        ),
                      ),
                    ),
                ],
              ),
          ],
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
    return Text(
      value ?? '—',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: c.textSecondary, fontSize: 12),
    );
  }
}

// ────────────────────────────────────────────────────────────
// 解析サマリー：記録・日記を集計した結果を保持する
// ────────────────────────────────────────────────────────────
class _AnalyticsSummary {
  final double? avgSleep; // 記録された日のみ平均
  final double? exerciseRate; // 0.0–1.0
  final double? studyRate; // 0.0–1.0
  final int streakDays; // 今日（未記録なら昨日）から遡る連続記録日数
  final int recordedDays; // 期間内で何か記録した日数
  final Map<String, int> moodDistribution; // 今日の気分の値別件数

  _AnalyticsSummary({
    required this.avgSleep,
    required this.exerciseRate,
    required this.studyRate,
    required this.streakDays,
    required this.recordedDays,
    required this.moodDistribution,
  });

  factory _AnalyticsSummary.from(
    List<MapEntry<String, Map<String, dynamic>>> records,
    List<MapEntry<String, Map<String, dynamic>>> diaries,
    List<String> dateRange,
  ) {
    final dateSet = dateRange.toSet();
    final relevant = records.where((e) => dateSet.contains(e.key)).toList();

    final sleeps = <double>[];
    int exerciseDone = 0, exerciseRecorded = 0;
    int studyDone = 0, studyRecorded = 0;
    final mood = <String, int>{};

    for (final e in relevant) {
      final sleep = numberOf(e.value, kSleepFieldId);
      if (sleep != null) sleeps.add(sleep);

      final exercise = flagOf(e.value, kExerciseFieldId);
      if (exercise != null) {
        exerciseRecorded++;
        if (exercise) exerciseDone++;
      }
      final study = flagOf(e.value, kStudyFieldId);
      if (study != null) {
        studyRecorded++;
        if (study) studyDone++;
      }
      final m = textOf(e.value, kMoodFieldId);
      if (m != null) mood[m] = (mood[m] ?? 0) + 1;
    }

    // ホームと同じ定義（記録か日記のどちらかがある日）で数える
    final recorded = recordedDates(records, diaries);
    return _AnalyticsSummary(
      avgSleep: sleeps.isEmpty
          ? null
          : sleeps.reduce((a, b) => a + b) / sleeps.length,
      exerciseRate: exerciseRecorded == 0
          ? null
          : exerciseDone / exerciseRecorded,
      studyRate: studyRecorded == 0 ? null : studyDone / studyRecorded,
      streakDays: calcStreak(recorded, DateTime.now()),
      recordedDays: recorded.where(dateSet.contains).length,
      moodDistribution: mood,
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
      return const _EmptyCard(message: 'まだ記録が足りない');
    }

    String rate(double? r) => r == null ? '—' : '${(r * 100).round()}%';
    final cards = <Widget>[
      _StatCard(
        label: '平均睡眠',
        value: s.avgSleep == null ? '—' : '${s.avgSleep!.toStringAsFixed(1)}h',
      ),
      _StatCard(label: '運動実施率', value: rate(s.exerciseRate)),
      _StatCard(label: '勉強実施率', value: rate(s.studyRate)),
      _StatCard(label: '連続記録', value: '${s.streakDays}日'),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // 横幅に応じてカード幅を調整（最低160）
        const spacing = 12.0;
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

// ────────────────────────────────────────────────────────────
// 追跡中の目標の進捗
//
// 行動項目ごとに1枚ずつカードを出す。チェック項目は達成率、数値項目は最新値。
// どちらも記録が無ければ「—」を出して「0%」「0」と区別する
// ―― まだ測っていないことと、測って0だったことは意味が違う。
// ────────────────────────────────────────────────────────────
class _GoalProgressSection extends StatelessWidget {
  final Goal goal;
  final List<MapEntry<String, Map<String, dynamic>>> records;

  const _GoalProgressSection({required this.goal, required this.records});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 目標そのもの。_SectionHeader の subtitle に入れると
        // 長いタイトルで見出し行が崩れるため、中身の先頭に置く。
        Text(
          goal.title,
          style: DetectiveTextStyles.cardTitle(
            color: c.textPrimary,
          ).copyWith(fontSize: 15),
        ),
        if (goal.metric.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            goal.metric,
            style: TextStyle(fontSize: 12, color: c.textSecondary, height: 1.4),
          ),
        ],
        const SizedBox(height: 4),
        Text(
          // 相談室ハブ・記録一覧と同じ文面（goal_progress に1本化してある）
          elapsedLabel(goal, DateTime.now()),
          style: TextStyle(fontSize: 11, color: c.textSecondary),
        ),
        const SizedBox(height: 14),
        if (goal.actions.isEmpty)
          const _EmptyCard(message: '毎日記録する項目は設定されていない')
        else ...[
          LayoutBuilder(
            builder: (context, constraints) {
              // 横幅に応じてカード幅を調整（_SummaryCards と同じ組み方）
              const spacing = 12.0;
              final available = constraints.maxWidth;
              final cardWidth = available >= 4 * 160 + 3 * spacing
                  ? (available - 3 * spacing) / 4
                  : (available - spacing) / 2;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final action in goal.actions)
                    SizedBox(
                      width: cardWidth,
                      child: _StatCard(
                        label: action.label,
                        value: _valueFor(action),
                        sub: _subFor(action),
                      ),
                    ),
                ],
              );
            },
          ),
          // 数値項目の推移。点が2つ以上ある項目だけ出す
          // （1点では推移にならず、最新値のカードで足りる）。
          for (final action in goal.numericActions)
            if (numericSeries(records, action.answerKey).length >= 2) ...[
              const SizedBox(height: 16),
              _NumericChart(
                label: action.label,
                unit: action.unit,
                target: action.target,
                series: numericSeries(records, action.answerKey),
              ),
            ],
        ],
      ],
    );
  }

  // カードに出す値。記録が無ければ「—」。
  String _valueFor(GoalAction action) {
    if (action.isNumeric) {
      final latest = latestNumeric(records, action.answerKey);
      if (latest == null) return '—';
      final text = formatNumber(latest);
      return action.unit.isEmpty ? text : '$text${action.unit}';
    }
    final rate = checkRate(records, action.answerKey);
    if (rate == null) return '—';
    return '${(rate * 100).round()}%';
  }

  // カードの値に添える一言。
  // チェック項目には母数を出す ―― 率だけだと「1日だけ答えて達成」も
  // 「14日続けて達成」もどちらも100%になり、区別が付かない。
  String? _subFor(GoalAction action) {
    if (action.isNumeric) {
      final count = numericSeries(records, action.answerKey).length;
      return count == 0 ? null : '$count回の記録';
    }
    final counts = checkCounts(records, action.answerKey);
    return counts.answered == 0 ? null : '${counts.done} / ${counts.answered}日';
  }
}

// 数値項目の推移（目標の数値項目・カスタムの数値項目で共用）。
//
// 棒ではなく折れ線にしているのは、記録が無い日を素直に「点が無い」で表せるため。
// 棒グラフだと未記録を 0 の高さで描くしかなく（睡眠グラフはそうしている）、
// 「記録していない日」と「記録して0だった日」が混ざる。
//
// 縦軸は値から決める（core/chart_scale.dart）。体重・歩数・分数と桁が違うので、
// 睡眠用の maxY 固定の棒グラフは流用できない。
class _NumericChart extends StatelessWidget {
  final String label;
  final String unit;
  final double? target;
  final List<({String date, double value})> series;

  const _NumericChart({
    required this.label,
    required this.unit,
    required this.target,
    required this.series,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final scale = numericChartScale(
      series.map((point) => point.value),
      target: target,
    );
    final goalLine = target;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              unit.isEmpty ? '$label の推移' : '$label の推移（$unit）',
              style: TextStyle(fontSize: 11, color: c.textSecondary),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                minY: scale.minY,
                maxY: scale.maxY,
                minX: 0,
                maxX: (series.length - 1).toDouble(),
                lineBarsData: [
                  LineChartBarData(
                    spots: [
                      for (var i = 0; i < series.length; i++)
                        FlSpot(i.toDouble(), series[i].value),
                    ],
                    isCurved: false,
                    color: c.gold,
                    barWidth: 2,
                    dotData: const FlDotData(show: true),
                  ),
                ],
                // 目標値は破線で。線がグラフの外に出ないよう縦軸の範囲にも含めてある
                extraLinesData: goalLine == null
                    ? const ExtraLinesData()
                    : ExtraLinesData(
                        horizontalLines: [
                          HorizontalLine(
                            y: goalLine,
                            color: c.textSecondary,
                            strokeWidth: 1,
                            dashArray: [4, 4],
                          ),
                        ],
                      ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: scale.interval,
                  getDrawingHorizontalLine: (value) =>
                      FlLine(color: c.cardBorder, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: scale.interval,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) => Text(
                        formatNumber(value),
                        style: TextStyle(fontSize: 10, color: c.textSecondary),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      reservedSize: 32,
                      getTitlesWidget: (value, meta) {
                        final index = value.round();
                        if (index < 0 || index >= series.length) {
                          return const SizedBox.shrink();
                        }
                        // 日付が詰まって読めなくなるので1つ飛ばしで出す
                        if (series.length > 6 && index % 2 != 0) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Transform.rotate(
                            angle: -0.4,
                            child: Text(
                              _shortDate(series[index].date),
                              style: TextStyle(
                                fontSize: 9,
                                color: c.textSecondary,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;

  /// 値に添える小さな補足（達成率の母数「9 / 12日」など）。null なら出さない。
  final String? sub;

  const _StatCard({required this.label, required this.value, this.sub});

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
          Text(label, style: TextStyle(fontSize: 11, color: c.textSecondary)),
          const SizedBox(height: 6),
          Text(
            value,
            style: DetectiveTextStyles.cardTitle(
              color: c.gold,
            ).copyWith(fontSize: 22),
          ),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(sub!, style: TextStyle(fontSize: 10, color: c.textSecondary)),
          ],
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// 分布パイチャート
// ────────────────────────────────────────────────────────────
class _PieCard extends StatelessWidget {
  final String title;
  final Map<String, int> distribution;
  const _PieCard({required this.title, required this.distribution});

  // 扇形の上のパーセント表示は labelColorOn()（app_colors.dart）で決める。
  // 以前は白で固定していたため、明るい扇形では 1.44:1 まで落ちて
  // パーセント表示が消えていた。

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (distribution.isEmpty) {
      return _EmptyCard(message: '$title の記録なし');
    }
    final total = distribution.values.fold<int>(0, (a, b) => a + b);
    final sortedEntries = distribution.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final palette = c.chartPalette;
    final sections = <PieChartSectionData>[];
    for (var i = 0; i < sortedEntries.length; i++) {
      final e = sortedEntries[i];
      final color = palette[i % palette.length];
      sections.add(
        PieChartSectionData(
          value: e.value.toDouble(),
          color: color,
          title: '${(e.value / total * 100).round()}%',
          titleStyle: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: labelColorOn(color),
          ),
          radius: 52,
        ),
      );
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
          Text(
            title,
            style: DetectiveTextStyles.cardTitle(
              color: c.textPrimary,
            ).copyWith(fontSize: 14),
          ),
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
          for (var i = 0; i < sortedEntries.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: palette[i % palette.length],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      sortedEntries[i].key,
                      style: TextStyle(fontSize: 11, color: c.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${sortedEntries[i].value}',
                    style: TextStyle(fontSize: 11, color: c.textSecondary),
                  ),
                ],
              ),
            ),
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
                    strokeWidth: 2,
                    color: c.gold,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '探偵が記録を読み返している…',
                  style: TextStyle(fontSize: 13, color: c.textSecondary),
                ),
              ],
            ),
          ] else if (hasText) ...[
            Text(
              text!,
              style: TextStyle(fontSize: 13, color: c.textPrimary, height: 1.6),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (generatedAt != null)
                  Text(
                    '記録: ${_formatTimestamp(generatedAt!)}',
                    style: TextStyle(fontSize: 10, color: c.textSecondary),
                  )
                else
                  const SizedBox.shrink(),
                TextButton.icon(
                  onPressed: onGenerate,
                  icon: Icon(Icons.refresh, size: 16, color: c.gold),
                  label: Text(
                    '再推理',
                    style: TextStyle(color: c.gold, fontSize: 12),
                  ),
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
                  foregroundColor: c.onAccent,
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
      child: Text(
        message,
        style: TextStyle(fontSize: 12, color: c.textSecondary),
      ),
    );
  }
}
