import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../core/question_schedule.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/detective_text_styles.dart';
import '../models/record_field.dart';
import '../services/firestore_service.dart';

// 日々の記録に並べる項目（記録の型）の設定画面。
//
// 項目の有効／無効・並び順・表に出す曜日・日記の材料にするかを決め、
// 自分の項目を足す。目標の行動項目はここに出さない（相談室で決め、
// 目標を閉じれば外れる。RecordField の説明を参照）。
//
// プリセットは消せず、使う／使わないを切り替えるだけ。足した項目は消せるが、
// 消すと過去の記録がその項目の値として読めなくなるので、先に「使わない」を勧める。
class FieldSettingsPage extends StatefulWidget {
  final String uid;

  const FieldSettingsPage({super.key, required this.uid});

  @override
  State<FieldSettingsPage> createState() => _FieldSettingsPageState();
}

class _FieldSettingsPageState extends State<FieldSettingsPage> {
  final FirestoreService _firestore = FirestoreService();

  bool _loading = true;
  bool _saving = false;
  List<RecordField> _fields = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final fields = await _firestore.getFields(widget.uid);
      if (!mounted) return;
      setState(() {
        _fields = fields;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showSnack('項目を読み込めなかった: $e');
    }
  }

  // 一覧を丸ごと保存する。画面の表示は先に変え、失敗したら知らせる。
  Future<void> _save(List<RecordField> fields) async {
    setState(() {
      _fields = fields;
      _saving = true;
    });
    try {
      await _firestore.saveFields(widget.uid, fields);
    } catch (e) {
      _showSnack('項目を保存できなかった: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _replace(RecordField updated) {
    _save([
      for (final field in _fields) field.id == updated.id ? updated : field,
    ]);
  }

  void _reorder(int oldIndex, int newIndex) {
    final fields = [..._fields];
    // ReorderableListView は「取り除く前の位置」で newIndex を渡してくる
    if (newIndex > oldIndex) newIndex -= 1;
    fields.insert(newIndex, fields.removeAt(oldIndex));
    _save(fields);
  }

  Future<void> _edit(RecordField field) async {
    final result = await showModalBottomSheet<_EditResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.cardBg,
      builder: (_) => _FieldEditorSheet(initial: field),
    );
    if (result == null || !mounted) return;
    if (result.delete) {
      _save(_fields.where((f) => f.id != field.id).toList());
    } else if (result.field != null) {
      _replace(result.field!);
    }
  }

  Future<void> _add() async {
    final result = await showModalBottomSheet<_EditResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.cardBg,
      builder: (_) => const _FieldEditorSheet(),
    );
    final field = result?.field;
    if (field == null || !mounted) return;
    _save([..._fields, field]);
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
              '記録する項目',
              style: DetectiveTextStyles.appBarTitle(color: c.appBarFg),
            ),
            const SizedBox(height: 2),
            Text(
              '― 日々の記録の型を決める ―',
              style: DetectiveTextStyles.appBarSubtitle(
                color: c.appBarSubtitle,
              ),
            ),
          ],
        ),
        actions: [
          if (_saving)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: c.goldLight,
                  strokeWidth: 2,
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: c.gold))
          : ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              header: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '長押しで並べ替え。タップで曜日や名前を変えられる。\n'
                  '追跡中の事件の項目は相談室で決める（ここには出ない）。',
                  style: TextStyle(
                    fontSize: 12,
                    color: c.textSecondary,
                    height: 1.5,
                  ),
                ),
              ),
              footer: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                  onPressed: _add,
                  icon: Icon(Icons.add, color: c.gold),
                  label: Text('項目を追加する', style: TextStyle(color: c.gold)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: c.gold),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              itemCount: _fields.length,
              onReorder: _reorder,
              itemBuilder: (context, index) {
                final field = _fields[index];
                return Padding(
                  key: ValueKey(field.id),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _FieldTile(
                    field: field,
                    onTap: () => _edit(field),
                    onToggle: (active) =>
                        _replace(field.copyWith(active: active)),
                  ),
                );
              },
            ),
    );
  }
}

// 一覧の1行。名前・型・曜日の要約と、使う／使わないのスイッチ。
class _FieldTile extends StatelessWidget {
  final RecordField field;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;

  const _FieldTile({
    required this.field,
    required this.onTap,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final notes = <String>[
      fieldKindLabel(field.kind),
      if (field.kind == FieldKind.numeric && field.unit.isNotEmpty) field.unit,
      describeWeekdays(field.weekdays),
      if (!field.useInDiary) '日記に使わない',
      if (field.source == FieldSource.consult) '相談室で追加',
    ];
    return Material(
      color: c.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(4)),
        side: BorderSide(color: c.cardBorder),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      field.label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: field.active ? c.textPrimary : c.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      notes.join(' ・ '),
                      style: TextStyle(fontSize: 11, color: c.textSecondary),
                    ),
                  ],
                ),
              ),
              Switch(
                value: field.active,
                onChanged: onToggle,
                activeThumbColor: c.onAccent,
                activeTrackColor: c.gold,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 編集シートの結果。field が入っていれば保存、delete なら削除。
class _EditResult {
  final RecordField? field;
  final bool delete;

  const _EditResult.save(RecordField this.field) : delete = false;
  const _EditResult.delete() : field = null, delete = true;
}

// 項目の追加・編集シート。initial が null なら新しい項目を作る。
//
// 型は作るときにだけ選べる。後から変えると、それまでの値が新しい型として
// 読めなくなる（「はい」を数値として読む、など）ため。
class _FieldEditorSheet extends StatefulWidget {
  final RecordField? initial;

  const _FieldEditorSheet({this.initial});

  @override
  State<_FieldEditorSheet> createState() => _FieldEditorSheetState();
}

class _FieldEditorSheetState extends State<_FieldEditorSheet> {
  late final TextEditingController _label;
  late final TextEditingController _unit;
  late final TextEditingController _choices;
  late FieldKind _kind;
  late List<int> _weekdays;
  late bool _useInDiary;
  String? _error;

  bool get _isNew => widget.initial == null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _label = TextEditingController(text: initial?.label ?? '');
    _unit = TextEditingController(text: initial?.unit ?? '');
    _choices = TextEditingController(text: initial?.choices.join('、') ?? '');
    _kind = initial?.kind ?? FieldKind.text;
    _weekdays = initial?.weekdays ?? RecordField.allWeekdays;
    _useInDiary = initial?.useInDiary ?? true;
  }

  @override
  void dispose() {
    _label.dispose();
    _unit.dispose();
    _choices.dispose();
    super.dispose();
  }

  // 「、」「,」「改行」のどれで区切っても選択肢として読む
  List<String> _parseChoices() => _choices.text
      .split(RegExp(r'[、,，\n]'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toSet()
      .toList();

  String? _validate() {
    if (_label.text.trim().isEmpty) return '名前を入れてくれ';
    if (_kind == FieldKind.choice && _parseChoices().length < 2) {
      return '選択肢は2つ以上必要だ';
    }
    return null;
  }

  void _submit() {
    // スナックバーはシートの裏に出て見えないので、シートの中に出す
    final error = _validate();
    setState(() => _error = error);
    if (error != null) return;
    final initial = widget.initial;
    final label = _label.text.trim();
    final unit = _kind == FieldKind.numeric ? _unit.text.trim() : '';
    final choices = _kind == FieldKind.choice ? _parseChoices() : <String>[];
    final field = initial == null
        ? RecordField(
            id: '$kCustomFieldPrefix${const Uuid().v4()}',
            label: label,
            kind: _kind,
            unit: unit,
            choices: choices,
            weekdays: _weekdays,
            source: FieldSource.self,
            useInDiary: _useInDiary,
          )
        : initial.copyWith(
            // プリセットの名前は変えさせない（分析室の見出しと食い違うため）
            label: initial.isCustom ? label : null,
            unit: unit,
            choices: choices,
            weekdays: _weekdays,
            useInDiary: _useInDiary,
          );
    Navigator.pop(context, _EditResult.save(field));
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('この項目を削除するか？'),
        content: const Text(
          '削除すると、これまでの記録もこの項目の値として読めなくなる。'
          '記録を残したいなら「使わない」に切り替えるだけにしておけ。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('削除する'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      Navigator.pop(context, const _EditResult.delete());
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final initial = widget.initial;
    final canRename = initial == null || initial.isCustom;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _isNew ? '項目を追加' : '項目を編集',
                style: DetectiveTextStyles.cardTitle(
                  color: c.textPrimary,
                ).copyWith(fontSize: 17),
              ),
              const SizedBox(height: 16),
              _Caption('名前'),
              TextField(
                controller: _label,
                enabled: canRename,
                style: TextStyle(color: c.textPrimary),
                decoration: _decoration(c, hint: '例：読んだページ数・今日の天気'),
              ),
              const SizedBox(height: 16),
              _Caption('記録のしかた'),
              if (_isNew)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final kind in FieldKind.values)
                      ChoiceChip(
                        label: Text(fieldKindLabel(kind)),
                        selected: _kind == kind,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _kind = kind),
                        selectedColor: c.goldLight,
                        backgroundColor: c.cardBg,
                        side: BorderSide(
                          color: _kind == kind ? c.gold : c.cardBorder,
                        ),
                        labelStyle: TextStyle(
                          color: _kind == kind ? c.caseNumberFg : c.textPrimary,
                        ),
                      ),
                  ],
                )
              else
                Text(
                  '${fieldKindLabel(_kind)}（作ったあとは変えられない）',
                  style: TextStyle(fontSize: 13, color: c.textSecondary),
                ),
              if (_kind == FieldKind.numeric) ...[
                const SizedBox(height: 16),
                _Caption('単位'),
                TextField(
                  controller: _unit,
                  style: TextStyle(color: c.textPrimary),
                  decoration: _decoration(c, hint: '例：kg・歩・分'),
                ),
              ],
              if (_kind == FieldKind.choice) ...[
                const SizedBox(height: 16),
                _Caption('選択肢（「、」で区切る）'),
                TextField(
                  controller: _choices,
                  style: TextStyle(color: c.textPrimary),
                  decoration: _decoration(c, hint: '例：晴れ、曇り、雨'),
                ),
              ],
              const SizedBox(height: 16),
              _Caption('表に出す曜日（${describeWeekdays(_weekdays)}）'),
              _WeekdayToggles(
                weekdays: _weekdays,
                onToggle: (day) =>
                    setState(() => _weekdays = toggleWeekday(_weekdays, day)),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '日記の材料にする',
                  style: TextStyle(fontSize: 14, color: c.textPrimary),
                ),
                subtitle: Text(
                  'オフにすると記録には残るが、探偵は日記の本文に書かない',
                  style: TextStyle(fontSize: 11, color: c.textSecondary),
                ),
                value: _useInDiary,
                onChanged: (v) => setState(() => _useInDiary = v),
                activeThumbColor: c.onAccent,
                activeTrackColor: c.gold,
              ),
              if (_error != null) ...[
                const SizedBox(height: 4),
                Text(
                  _error!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: c.gold,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  if (initial != null && initial.isCustom)
                    TextButton(
                      onPressed: _confirmDelete,
                      child: Text(
                        '削除',
                        style: TextStyle(color: c.textSecondary),
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'キャンセル',
                      style: TextStyle(color: c.textSecondary),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: c.gold,
                      foregroundColor: c.onAccent,
                    ),
                    child: Text(_isNew ? '追加する' : '保存する'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration(AppColors c, {required String hint}) {
    return InputDecoration(
      isDense: true,
      hintText: hint,
      hintStyle: TextStyle(fontSize: 13, color: c.textSecondary),
      filled: true,
      fillColor: c.background,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: c.cardBorder),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: c.cardBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: c.gold, width: 1.5),
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  final String text;

  const _Caption(this.text);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: TextStyle(fontSize: 12, color: c.textSecondary)),
    );
  }
}

// 月〜日の曜日トグル。選択中は gold の塗り＋onAccent の文字
class _WeekdayToggles extends StatelessWidget {
  final List<int> weekdays;
  final ValueChanged<int> onToggle;

  const _WeekdayToggles({required this.weekdays, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: List.generate(7, (i) {
        final weekday = i + 1;
        final selected = weekdays.contains(weekday);
        return Semantics(
          button: true,
          selected: selected,
          label: '${kWeekdayLabels[i]}曜日',
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => onToggle(weekday),
            child: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? c.gold : Colors.transparent,
                border: Border.all(color: selected ? c.gold : c.cardBorder),
              ),
              child: ExcludeSemantics(
                child: Text(
                  kWeekdayLabels[i],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    color: selected ? c.onAccent : c.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
