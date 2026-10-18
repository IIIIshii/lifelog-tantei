import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../core/daily_record.dart';
import '../core/goal_progress.dart';
import '../core/streak.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/detective_text_styles.dart';
import '../models/goal.dart';
import '../models/record_field.dart';
import '../roles/roles.dart';
import '../services/firestore_service.dart';
import '../services/gemini_service.dart';
import '../widgets/section_label.dart';
import 'field_settings_page.dart';
import 'record_tell_sheet.dart';

// 日々の記録（チェックシート）。睡眠時間・今日の気分・午前にしたこと・カスタム項目・
// 目標の行動項目といった「事実」を、表に書き込む形で記録する画面。
//
// 日記の聴取（DiaryPage）から事実の確認を切り出したのがこの画面。聴取は
// ここに書かれた内容を読んでから、日記に書く出来事の深掘りだけを行う。
//
// 1項目ずつ書く代わりに、「探偵に話す」（RecordTellSheet）でまとめて話し、
// AI に表へ振り分けさせることもできる（確認してから入れる）。
//
// 保存は項目ごとに即時（テキスト・数値は打ち終わりを少し待ってから）。
// 「保存」ボタンを置かないのは、朝に睡眠だけ、夜に残りを書く、のように
// 1日の中で何度も開いて書き足す使い方を想定しているため。
//
// continueToDiary を true にすると、下部に「日記へ進む／今日はここまで」を出し、
// pop の戻り値（true なら日記へ）で呼び出し側（MainShell の捜査の動線）が次を決める。
class RecordSheetPage extends StatefulWidget {
  final String uid;

  /// 対象の日付（YYYY-MM-DD）。省略すると今日。
  final String? date;

  /// 捜査の動線から開かれたか（下部に日記へ進むボタンを出す）。
  final bool continueToDiary;

  const RecordSheetPage({
    super.key,
    required this.uid,
    this.date,
    this.continueToDiary = false,
  });

  @override
  State<RecordSheetPage> createState() => _RecordSheetPageState();
}

class _RecordSheetPageState extends State<RecordSheetPage> {
  // 打ち終わりを待つ時間。キー入力のたびに書き込むと、1文字ごとに
  // Firestore への書き込みが走るため。
  static const _saveDelay = Duration(milliseconds: 700);

  final FirestoreService _firestore = FirestoreService();

  late DateTime _day;
  bool _loading = true;
  bool _failed = false;

  List<RecordField> _rows = const [];
  List<Goal> _goals = const [];
  final Map<String, Object?> _values = {};

  // まだ書き込んでいない変更（項目 id → 値。null は消す）
  final Map<String, Object?> _pending = {};
  Timer? _saveTimer;

  // テキスト・数値欄のコントローラ。日付を切り替えるたびに作り直す。
  final Map<String, TextEditingController> _controllers = {};

  // 「探偵に話す」で使う。開いたときに初めて作る。
  // 振り分けは人格を使わないので、担当探偵の設定は読まずに既定のロールで作る。
  GeminiService? _gemini;

  @override
  void initState() {
    super.initState();
    final date = widget.date == null ? null : DateTime.tryParse(widget.date!);
    final base = date ?? DateTime.now();
    _day = DateTime(base.year, base.month, base.day);
    _load();
  }

  @override
  void dispose() {
    // 打ちかけの値を落とさない。書き込みは Firestore の手元のキューに積まれるので、
    // 画面を閉じた後でも送られる（待たずに閉じてよい）。
    _flush();
    _saveTimer?.cancel();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String get _dateKey => dateKey(_day);

  bool get _isToday => _dateKey == dateKey(DateTime.now());

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final fieldsFuture = _firestore.getFields(widget.uid);
      final goalsFuture = _firestore.getGoals(widget.uid);
      final recordFuture = _firestore.getRecord(widget.uid, _dateKey);
      final fields = await fieldsFuture;
      final goals = await goalsFuture;
      final record = await recordFuture;
      if (!mounted) return;

      final rows = fieldsForDay(fields, goals, _day);
      for (final controller in _controllers.values) {
        controller.dispose();
      }
      _controllers.clear();
      _values.clear();
      for (final field in rows) {
        final value = valueOf(record, field.id);
        _values[field.id] = value;
        if (field.kind == FieldKind.numeric || field.kind == FieldKind.text) {
          _controllers[field.id] = TextEditingController(
            text: switch (value) {
              num v => formatNumber(v.toDouble()),
              String v => v,
              _ => '',
            },
          );
        }
      }
      setState(() {
        _rows = rows;
        _goals = goals;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  // 日付を動かす。未来の日は記録しない（まだ起きていない事実を書く場所ではないため）。
  Future<void> _moveDay(int delta) async {
    final next = DateTime(_day.year, _day.month, _day.day + delta);
    final today = DateTime.now();
    if (next.isAfter(DateTime(today.year, today.month, today.day))) return;
    _flush();
    setState(() => _day = next);
    await _load();
  }

  // 値を変える。テキスト・数値は打ち終わりを待ち、選ぶだけの項目はすぐ書く。
  void _set(RecordField field, Object? raw, {bool immediate = false}) {
    final value = normalizeInput(field, raw);
    setState(() => _values[field.id] = value);
    _pending[field.id] = value;
    _saveTimer?.cancel();
    if (immediate) {
      _flush();
    } else {
      _saveTimer = Timer(_saveDelay, _flush);
    }
  }

  void _flush() {
    _saveTimer?.cancel();
    if (_pending.isEmpty) return;
    final changes = Map<String, Object?>.of(_pending);
    final date = _dateKey;
    _pending.clear();
    _firestore.saveRecordValues(widget.uid, date, changes).catchError((
      Object e,
    ) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('記録を保存できなかった: $e')));
    });
  }

  // 「探偵に話す」：まとめて話した内容を表に振り分け、選んだものを入れる。
  // 入れた値は表で手入力したのと同じ経路（_values / _pending → _flush）で保存する。
  Future<void> _openTell() async {
    _flush();
    final gemini = _gemini ??= GeminiService(
      dotenv.env['GEMINI_API_KEY'] ?? '',
      kDefaultRoleKey,
    );
    final accepted = await showModalBottomSheet<Map<String, Object>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.cardBg,
      builder: (_) => RecordTellSheet(
        fields: _rows,
        currentValues: Map.of(_values),
        gemini: gemini,
      ),
    );
    if (accepted == null || accepted.isEmpty || !mounted) return;

    setState(() {
      for (final entry in accepted.entries) {
        _values[entry.key] = entry.value;
        _pending[entry.key] = entry.value;
        // テキスト・数値欄は入力欄の文字も差し替える（表示と保存値を揃える）
        final controller = _controllers[entry.key];
        if (controller != null) {
          controller.text = switch (entry.value) {
            num v => formatNumber(v.toDouble()),
            final v => '$v',
          };
        }
      }
    });
    _flush();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${accepted.length}件を表に入れた')));
  }

  Future<void> _openFieldSettings() async {
    _flush();
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => FieldSettingsPage(uid: widget.uid)),
    );
    if (mounted) await _load();
  }

  String _dateLabel() {
    const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
    return '${_day.month}月${_day.day}日（${weekdays[_day.weekday - 1]}）';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final progress = recordProgress(_rows, {'values': _values});

    // 生活の記録と目標の項目を分けて見せる（目標ごとに見出しを付ける）
    final lifeRows = _rows.where((f) => !f.isGoal).toList();
    final goalRows = <String, List<RecordField>>{};
    for (final field in _rows.where((f) => f.isGoal)) {
      (goalRows[field.goalId!] ??= []).add(field);
    }

    return PopScope(
      // 戻る操作でも打ちかけの値を書いてから閉じる
      onPopInvokedWithResult: (didPop, _) => _flush(),
      child: Scaffold(
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
                '日々の記録',
                style: DetectiveTextStyles.appBarTitle(color: c.appBarFg),
              ),
              const SizedBox(height: 2),
              Text(
                '― 事実を書き留める ―',
                style: DetectiveTextStyles.appBarSubtitle(
                  color: c.appBarSubtitle,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.tune),
              tooltip: '記録する項目を変える',
              onPressed: _openFieldSettings,
            ),
          ],
        ),
        body: Column(
          children: [
            _DateBar(
              label: _dateLabel(),
              progress: _loading ? null : progress,
              canGoNext: !_isToday,
              onPrev: () => _moveDay(-1),
              onNext: () => _moveDay(1),
            ),
            // 1項目ずつ書く代わりに、まとめて話して埋める入口
            if (!_loading && _rows.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _openTell,
                    icon: Icon(Icons.record_voice_over, color: c.gold),
                    label: Text(
                      '探偵に話して埋める',
                      style: TextStyle(
                        color: c.gold,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: c.gold),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: _loading
                  ? Center(child: CircularProgressIndicator(color: c.gold))
                  : ListView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      children: [
                        if (_failed)
                          _Notice(message: '記録を読み込めなかった。日付を切り替えて再試行してくれ。')
                        else if (_rows.isEmpty)
                          _Notice(message: 'この日に記録する項目が無い。右上から項目を設定できる。')
                        else ...[
                          if (lifeRows.isNotEmpty) ...[
                            const SectionLabel(
                              '生活の記録',
                              icon: Icons.fact_check_outlined,
                            ),
                            const SizedBox(height: 10),
                            for (final field in lifeRows) _buildRow(field),
                          ],
                          for (final entry in goalRows.entries) ...[
                            const SizedBox(height: 18),
                            SectionLabel(
                              _goalById(entry.key).title,
                              icon: Icons.flag_outlined,
                            ),
                            // 今どの段階を追っているかを、記録する項目の上に添える
                            if (stepLabel(_goalById(entry.key)) case final step?)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  step,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: c.textSecondary,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 10),
                            for (final field in entry.value) _buildRow(field),
                          ],
                        ],
                      ],
                    ),
            ),
            if (widget.continueToDiary) _buildExit(c),
          ],
        ),
      ),
    );
  }

  Goal _goalById(String goalId) =>
      _goals.firstWhere((g) => g.id == goalId, orElse: () => const Goal());

  Widget _buildRow(RecordField field) {
    final c = context.colors;
    final value = _values[field.id];
    final filled = isFilled(value);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: filled ? c.gold : c.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    field.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                    ),
                  ),
                ),
                if (filled)
                  Icon(Icons.check_circle, size: 16, color: c.gold)
                else
                  Text(
                    '未記入',
                    style: TextStyle(fontSize: 11, color: c.textSecondary),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _buildInput(field, value),
          ],
        ),
      ),
    );
  }

  Widget _buildInput(RecordField field, Object? value) {
    switch (field.kind) {
      case FieldKind.numeric:
        return SizedBox(
          width: 160,
          child: _SheetTextField(
            controller: _controllers[field.id]!,
            hint: '数字',
            suffix: field.unit,
            numeric: true,
            onChanged: (text) => _set(field, text),
          ),
        );
      case FieldKind.text:
        return _SheetTextField(
          controller: _controllers[field.id]!,
          hint: '書き留める…',
          onChanged: (text) => _set(field, text),
        );
      case FieldKind.yesNo:
        return _ChipChoices(
          options: [yesNoLabel(field, true), yesNoLabel(field, false)],
          selected: value is bool ? yesNoLabel(field, value) : null,
          onSelected: (label) => _set(
            field,
            label == null ? null : label == yesNoLabel(field, true),
            immediate: true,
          ),
        );
      case FieldKind.choice:
        return _ChipChoices(
          options: field.choices,
          selected: value is String ? value : null,
          onSelected: (label) => _set(field, label, immediate: true),
        );
    }
  }

  // 捜査の動線から開かれたときの行き先。日記へ続けるか、ここで切り上げるか。
  Widget _buildExit(AppColors c) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.textSecondary,
                  side: BorderSide(color: c.cardBorder),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('今日はここまで'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.gold,
                  foregroundColor: c.onAccent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('日記へ進む'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 日付の切り替えと記入状況の帯。
class _DateBar extends StatelessWidget {
  final String label;
  final ({int filled, int total})? progress;
  final bool canGoNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _DateBar({
    required this.label,
    required this.progress,
    required this.canGoNext,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = progress;
    return Container(
      color: c.cardBg,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            color: c.gold,
            tooltip: '前の日',
            onPressed: onPrev,
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: c.textPrimary,
                  ),
                ),
                if (p != null && p.total > 0)
                  Text(
                    '記入 ${p.filled} / ${p.total}',
                    style: TextStyle(fontSize: 11, color: c.textSecondary),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            color: c.gold,
            disabledColor: c.cardBorder,
            tooltip: '次の日',
            onPressed: canGoNext ? onNext : null,
          ),
        ],
      ),
    );
  }
}

// 表の入力欄（テキスト・数値）。
class _SheetTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final String suffix;
  final bool numeric;
  final ValueChanged<String> onChanged;

  const _SheetTextField({
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.suffix = '',
    this.numeric = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.multiline,
      minLines: 1,
      maxLines: numeric ? 1 : 3,
      style: TextStyle(fontSize: 14, color: c.textPrimary),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: TextStyle(fontSize: 13, color: c.textSecondary),
        suffixText: suffix.isEmpty ? null : suffix,
        suffixStyle: TextStyle(fontSize: 13, color: c.textSecondary),
        filled: true,
        fillColor: c.background,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: c.cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: c.gold, width: 1.5),
        ),
      ),
    );
  }
}

// 選ぶだけの項目（はい／いいえ・選択肢）。選んでいるものをもう一度押すと未記入に戻る。
//
// 選択中の面は goldLight、その上の文字は caseNumberFg（面と前景のトークンを取り違えると
// コントラストが破綻する。AppColors の説明を参照）。
class _ChipChoices extends StatelessWidget {
  final List<String> options;
  final String? selected;
  final ValueChanged<String?> onSelected;

  const _ChipChoices({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          ChoiceChip(
            label: Text(option),
            selected: option == selected,
            showCheckmark: false,
            onSelected: (on) => onSelected(on ? option : null),
            selectedColor: c.goldLight,
            backgroundColor: c.cardBg,
            side: BorderSide(color: option == selected ? c.gold : c.cardBorder),
            labelStyle: TextStyle(
              fontSize: 13,
              color: option == selected ? c.caseNumberFg : c.textPrimary,
              fontWeight: option == selected
                  ? FontWeight.bold
                  : FontWeight.normal,
            ),
          ),
      ],
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
