import 'package:flutter/material.dart';

import '../core/daily_record.dart';
import '../core/health_daily.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/detective_text_styles.dart';
import '../models/record_field.dart';
import '../services/firestore_service.dart';
import '../services/health_service.dart';
import '../widgets/section_label.dart';

// 端末（Health Connect）と連携する画面。記録する項目の設定（FieldSettingsPage）から開く。
//
// 流れ: Health Connect が使えるか確かめる → 読み取りの権限を求める →
// 直近30日の記録を読む → 見つかった種類を「歩数（昨日 8231歩）」のように並べる →
// チェックしたものを記録の型に足す。
//
// 足すのは記録が見つかった種類だけ。持っているウォッチが記録しない種類まで並べると、
// 表と設定が使わない項目で埋まるため。すでに使っている項目は一覧に出さない。
// ウォッチを替えたときは、この画面を開き直せば新しく見つかった種類を足せる。
//
// pop の戻り値は、項目を足したら true（呼び出し側は一覧を読み直す）。
class HealthConnectPage extends StatefulWidget {
  final String uid;

  /// 今の記録の型。使っている項目を一覧から外すのに使う。
  final List<RecordField> fields;

  const HealthConnectPage({super.key, required this.uid, required this.fields});

  @override
  State<HealthConnectPage> createState() => _HealthConnectPageState();
}

enum _Step {
  checking, // Health Connect が使えるか確かめている
  unsupported, // この端末では使えない
  needsInstall, // Health Connect のアプリを入れる必要がある
  ready, // 使える。まだ連携していない
  scanning, // 記録を探している
  found, // 探し終えた
}

class _HealthConnectPageState extends State<HealthConnectPage> {
  final HealthService _health = HealthService.instance;
  final FirestoreService _firestore = FirestoreService();

  _Step _step = _Step.checking;
  bool _linked = false;
  bool _saving = false;

  // 見つかった記録のうち、まだ使っていない項目のもの
  List<HealthFinding> _findings = const [];

  // 見つかった記録の数（使っている項目のものも含む）。何も読めなかったのか、
  // 全部もう使っているのかを言い分けるために持つ。
  int _foundCount = 0;

  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() => _step = _Step.checking);
    final availability = await _health.availability();
    final linked = await _health.isLinked();
    if (!mounted) return;
    setState(() {
      _linked = linked;
      _step = switch (availability) {
        HealthAvailability.available => _Step.ready,
        HealthAvailability.needsInstall => _Step.needsInstall,
        HealthAvailability.unsupported => _Step.unsupported,
      };
    });
    // 連携済みなら、開いたらすぐ探す（ウォッチを替えたときに足す用途のため）
    if (linked && availability == HealthAvailability.available) await _scan();
  }

  Future<void> _connect() async {
    try {
      await _health.requestAccess();
    } catch (e) {
      _showSnack('Health Connect の許可画面を開けなかった: $e');
      return;
    }
    await _scan();
  }

  Future<void> _scan() async {
    setState(() => _step = _Step.scanning);
    List<HealthFinding> all;
    try {
      all = await _health.scanRecent();
    } catch (e) {
      if (!mounted) return;
      setState(() => _step = _Step.ready);
      _showSnack('記録を読めなかった: $e');
      return;
    }
    // 何か1つでも読めたら、この端末は連携済みにする（表を開いたときに読みにいく）
    if (all.isNotEmpty) {
      await _health.setLinked(true);
    }
    if (!mounted) return;
    final inUse = {
      for (final field in widget.fields)
        if (field.active) field.id,
    };
    final fresh = [
      for (final finding in all)
        if (!inUse.contains(finding.metric.fieldId)) finding,
    ];
    setState(() {
      _linked = _linked || all.isNotEmpty;
      _foundCount = all.length;
      _findings = fresh;
      _selected
        ..clear()
        ..addAll(fresh.map((f) => f.metric.fieldId));
      _step = _Step.found;
    });
  }

  Future<void> _add() async {
    final metrics = [
      for (final finding in _findings)
        if (_selected.contains(finding.metric.fieldId)) finding.metric,
    ];
    if (metrics.isEmpty) return;
    setState(() => _saving = true);
    try {
      await _firestore.addHealthFields(widget.uid, metrics);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showSnack('項目を加えられなかった: $e');
    }
  }

  Future<void> _unlink() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('端末からの読み取りを止めるか？'),
        content: const Text(
          '表を開いても、端末の記録を読みにいかなくなる。'
          'これまでに入れた値と項目はそのまま残る。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('止める'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _health.unlink();
    if (!mounted) return;
    setState(() {
      _linked = false;
      _findings = const [];
      _foundCount = 0;
      _selected.clear();
      _step = _Step.ready;
    });
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
              '端末と連携',
              style: DetectiveTextStyles.appBarTitle(color: c.appBarFg),
            ),
            const SizedBox(height: 2),
            Text(
              '― ウォッチの記録を表に入れる ―',
              style: DetectiveTextStyles.appBarSubtitle(
                color: c.appBarSubtitle,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [..._body(c)],
              ),
            ),
            if (_step == _Step.found && _findings.isNotEmpty) _buildAdd(c),
          ],
        ),
      ),
    );
  }

  Iterable<Widget> _body(AppColors c) sync* {
    yield _Paragraph(
      'スマートウォッチのアプリ（Fitbit・Samsung Health など）が Health Connect に'
      '書いた記録を読み、日々の記録の表に入れる。'
      '入るのは空いている欄だけで、自分で書いた値は上書きしない。',
    );
    yield const SizedBox(height: 16);

    switch (_step) {
      case _Step.checking:
      case _Step.scanning:
        yield Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Column(
            children: [
              CircularProgressIndicator(color: c.gold),
              const SizedBox(height: 12),
              Text(
                _step == _Step.scanning ? 'ここ30日の記録を探している…' : '確かめている…',
                style: TextStyle(fontSize: 13, color: c.textSecondary),
              ),
            ],
          ),
        );
      case _Step.unsupported:
        yield const _Notice('この端末では Health Connect を使えない（Android 9 以降が必要）。');
      case _Step.needsInstall:
        yield const _Notice(
          'Health Connect のアプリが入っていないか、古くなっている。'
          '入れてから戻ってきて「確かめ直す」を押してくれ。',
        );
        yield const SizedBox(height: 12);
        yield _PrimaryButton(
          label: 'Health Connect を入れる',
          onPressed: _health.installHealthConnect,
        );
        yield const SizedBox(height: 8);
        yield _SecondaryButton(label: '確かめ直す', onPressed: _check);
      case _Step.ready:
        yield _PrimaryButton(
          label: 'Health Connect と連携する',
          onPressed: _connect,
        );
        yield const SizedBox(height: 8);
        yield _Paragraph('次の画面で、読んでよい種類を選べる。許可しなかった種類は読まない。', small: true);
      case _Step.found:
        yield* _buildFound(c);
    }
  }

  Iterable<Widget> _buildFound(AppColors c) sync* {
    if (_foundCount == 0) {
      yield const _Notice(
        'ここ30日の記録が見つからなかった。'
        'ウォッチのアプリの設定で Health Connect への書き込みを有効にしたか、'
        'Health Connect の画面で読み取りを許可したかを確かめて、もう一度探してくれ。',
      );
    } else if (_findings.isEmpty) {
      yield const _Notice('見つかった記録は、すべてもう表の項目に入っている。');
    } else {
      yield _Paragraph('記録が見つかった種類だ。表に加える項目を選んでくれ。');
      String? group;
      for (final finding in _findings) {
        if (finding.metric.group != group) {
          group = finding.metric.group;
          yield const SizedBox(height: 16);
          yield SectionLabel(group, icon: Icons.watch_outlined);
          yield const SizedBox(height: 4);
        }
        yield _buildFinding(c, finding);
      }
    }
    yield const SizedBox(height: 16);
    yield _SecondaryButton(label: 'もう一度探す', onPressed: _scan);
    if (_linked) {
      yield const SizedBox(height: 8);
      yield Center(
        child: TextButton(
          onPressed: _unlink,
          child: Text(
            '端末からの読み取りを止める',
            style: TextStyle(fontSize: 13, color: c.textSecondary),
          ),
        ),
      );
    }
  }

  Widget _buildFinding(AppColors c, HealthFinding finding) {
    final metric = finding.metric;
    final id = metric.fieldId;
    final value = formatValue(metric.toField(), finding.value) ?? '';
    final notes = [
      '${_dayLabel(finding.day)} $value',
      if (!metric.shareWithAi) 'AIに送らない',
    ];
    return CheckboxListTile(
      value: _selected.contains(id),
      onChanged: (on) => setState(() {
        if (on == true) {
          _selected.add(id);
        } else {
          _selected.remove(id);
        }
      }),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      controlAffinity: ListTileControlAffinity.leading,
      activeColor: c.gold,
      checkColor: c.onAccent,
      title: Text(
        metric.label,
        style: TextStyle(fontSize: 14, color: c.textPrimary),
      ),
      subtitle: Text(
        notes.join(' ・ '),
        style: TextStyle(fontSize: 12, color: c.textSecondary),
      ),
    );
  }

  Widget _buildAdd(AppColors c) {
    final count = _selected.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: count == 0 || _saving ? null : _add,
          style: ElevatedButton.styleFrom(
            backgroundColor: c.gold,
            foregroundColor: c.onAccent,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: Text(_saving ? '加えている…' : '$count件を項目に加える'),
        ),
      ),
    );
  }

  String _dayLabel(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(DateTime(day.year, day.month, day.day));
    return switch (diff.inDays) {
      0 => '今日',
      1 => '昨日',
      _ => '${day.month}月${day.day}日',
    };
  }
}

class _Paragraph extends StatelessWidget {
  final String text;
  final bool small;

  const _Paragraph(this.text, {this.small = false});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Text(
      text,
      style: TextStyle(
        fontSize: small ? 12 : 13,
        height: 1.6,
        color: small ? c.textSecondary : c.textPrimary,
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final String message;

  const _Notice(this.message);

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

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _PrimaryButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: c.gold,
          foregroundColor: c.onAccent,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: Text(label),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _SecondaryButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: c.gold,
          side: BorderSide(color: c.gold),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: Text(label),
      ),
    );
  }
}
