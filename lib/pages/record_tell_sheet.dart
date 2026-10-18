import 'package:flutter/material.dart';

import '../core/daily_record.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/detective_text_styles.dart';
import '../models/record_field.dart';
import '../services/gemini_service.dart';
import '../services/speech_service.dart';

// 「探偵に話す」シート。今日のことをまとめて話すと（音声入力も使える）、
// AI が日々の記録の表の各項目に振り分け、確認してから表に入れる。
//
// 振り分けた結果をそのまま保存しないのは、AI の取り出しには取り違えがありうるため。
// 提案を1件ずつ見せ、入れるものを選ばせる。既に値がある項目への提案は
// 「上書き」として最初は外しておき、手で書いた値を勝手に消さない。
//
// pop の戻り値は「項目 id → 入れる値」。入れるものが無ければ null。
// 保存は呼び出し側（RecordSheetPage）が表の他の入力と同じ経路で行う。
class RecordTellSheet extends StatefulWidget {
  /// その日の表に並んでいる項目（並び順のまま）
  final List<RecordField> fields;

  /// 表に今入っている値（項目 id → 値）
  final Map<String, Object?> currentValues;

  final GeminiService gemini;

  const RecordTellSheet({
    super.key,
    required this.fields,
    required this.currentValues,
    required this.gemini,
  });

  @override
  State<RecordTellSheet> createState() => _RecordTellSheetState();
}

enum _Stage { input, extracting, review }

class _RecordTellSheetState extends State<RecordTellSheet> {
  final TextEditingController _controller = TextEditingController();

  _Stage _stage = _Stage.input;
  bool _listening = false;
  String _baseText = ''; // 音声認識を始めた時点の文。認識結果はこの後ろに足す
  String? _error;

  List<RecordProposal> _proposals = const [];
  final Set<String> _selected = {}; // 表に入れる提案の項目 id

  @override
  void dispose() {
    if (_listening) SpeechService.instance.stopListening();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _toggleMic() async {
    final speech = SpeechService.instance;
    if (_listening) {
      await speech.stopListening();
      if (mounted) setState(() => _listening = false);
      return;
    }
    _baseText = _controller.text;
    final ok = await speech.startListening(
      onResult: (text) {
        final joined = _baseText.isEmpty ? text : '$_baseText$text';
        _controller.value = TextEditingValue(
          text: joined,
          selection: TextSelection.collapsed(offset: joined.length),
        );
      },
      onDone: () {
        if (mounted) setState(() => _listening = false);
      },
    );
    if (!mounted) return;
    if (!ok) {
      setState(() => _error = 'マイクの使用が許可されていない');
      return;
    }
    setState(() {
      _listening = true;
      _error = null;
    });
  }

  Future<void> _extract() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    if (_listening) {
      await SpeechService.instance.stopListening();
      _listening = false;
    }
    setState(() {
      _stage = _Stage.extracting;
      _error = null;
    });
    try {
      final raw = await widget.gemini.extractRecordValues(
        text: text,
        fields: widget.fields,
      );
      if (!mounted) return;
      final proposals = proposalsFromExtraction(
        widget.fields,
        raw,
        widget.currentValues,
      );
      setState(() {
        _proposals = proposals;
        // 空いている項目への提案だけ最初から選んでおく（上書きは選び直させる）
        _selected
          ..clear()
          ..addAll([
            for (final p in proposals)
              if (p.current == null) p.field.id,
          ]);
        _stage = _Stage.review;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.input;
        _error = '振り分けられなかった: $e';
      });
    }
  }

  void _apply() {
    final accepted = <String, Object>{
      for (final p in _proposals)
        if (_selected.contains(p.field.id)) p.field.id: p.value,
    };
    Navigator.pop(context, accepted.isEmpty ? null : accepted);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.record_voice_over, color: c.gold, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '探偵に話す',
                      style: DetectiveTextStyles.cardTitle(
                        color: c.textPrimary,
                      ).copyWith(fontSize: 17),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _stage == _Stage.review
                      ? '表に入れるものを選んでくれ。'
                      : '今日のことをまとめて話してくれ。表の項目に振り分けて下書きにする。',
                  style: TextStyle(fontSize: 12, color: c.textSecondary),
                ),
                const SizedBox(height: 14),
                ...switch (_stage) {
                  _Stage.input => _buildInput(c),
                  _Stage.extracting => _buildExtracting(c),
                  _Stage.review => _buildReview(c),
                },
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildInput(AppColors c) {
    return [
      TextField(
        controller: _controller,
        minLines: 4,
        maxLines: 8,
        autofocus: true,
        style: TextStyle(fontSize: 14, color: c.textPrimary, height: 1.5),
        decoration: InputDecoration(
          hintText: _listening
              ? '聞き取り中…'
              : '例：6時間半寝た。午前は授業、午後は図書館でレポート。夕方に少し走った。気分は良い。',
          hintStyle: TextStyle(fontSize: 13, color: c.textSecondary),
          filled: true,
          fillColor: c.background,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: c.cardBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: c.gold, width: 1.5),
          ),
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 8),
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
          // マイク。録音中は塗りを gold にして、止められることを示す
          Semantics(
            button: true,
            label: _listening ? '音声入力を止める' : '音声で入力する',
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _toggleMic,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _listening ? c.gold : c.background,
                  border: Border.all(color: _listening ? c.gold : c.cardBorder),
                ),
                child: Icon(
                  _listening ? Icons.mic : Icons.mic_none,
                  color: _listening ? c.onAccent : c.textPrimary,
                ),
              ),
            ),
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: _extract,
            icon: const Icon(Icons.auto_fix_high, size: 18),
            label: const Text('表に振り分ける'),
            style: ElevatedButton.styleFrom(
              backgroundColor: c.gold,
              foregroundColor: c.onAccent,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _buildExtracting(AppColors c) {
    return [
      const SizedBox(height: 24),
      Center(child: CircularProgressIndicator(color: c.gold)),
      const SizedBox(height: 12),
      Center(
        child: Text(
          '探偵が書き写している…',
          style: TextStyle(fontSize: 13, color: c.textSecondary),
        ),
      ),
      const SizedBox(height: 24),
    ];
  }

  List<Widget> _buildReview(AppColors c) {
    final retry = TextButton(
      onPressed: () => setState(() => _stage = _Stage.input),
      child: Text('言い直す', style: TextStyle(color: c.textSecondary)),
    );
    if (_proposals.isEmpty) {
      return [
        Text(
          '表に入れられることが見つからなかった。項目に関わることを話してくれ。',
          style: TextStyle(fontSize: 13, color: c.textPrimary, height: 1.5),
        ),
        const SizedBox(height: 12),
        Align(alignment: Alignment.centerRight, child: retry),
      ];
    }
    return [
      Container(
        decoration: BoxDecoration(
          color: c.background,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: c.cardBorder),
        ),
        child: Column(
          children: [
            for (var i = 0; i < _proposals.length; i++) ...[
              if (i > 0) Divider(height: 1, color: c.cardBorder),
              _ProposalTile(
                proposal: _proposals[i],
                selected: _selected.contains(_proposals[i].field.id),
                onChanged: (on) => setState(() {
                  final id = _proposals[i].field.id;
                  on ? _selected.add(id) : _selected.remove(id);
                }),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          retry,
          const Spacer(),
          ElevatedButton(
            onPressed: _selected.isEmpty ? null : _apply,
            style: ElevatedButton.styleFrom(
              backgroundColor: c.gold,
              foregroundColor: c.onAccent,
            ),
            child: Text('表に入れる（${_selected.length}件）'),
          ),
        ],
      ),
    ];
  }
}

// 提案1件。何がどう変わるかを「今の値 → 新しい値」で見せる。
class _ProposalTile extends StatelessWidget {
  final RecordProposal proposal;
  final bool selected;
  final ValueChanged<bool> onChanged;

  const _ProposalTile({
    required this.proposal,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final field = proposal.field;
    final next = formatValue(field, proposal.value) ?? '';
    final current = formatValue(field, proposal.current);
    return CheckboxListTile(
      value: selected,
      onChanged: (v) => onChanged(v ?? false),
      activeColor: c.gold,
      checkColor: c.onAccent,
      controlAffinity: ListTileControlAffinity.leading,
      dense: true,
      title: Text(
        field.isGoal ? '${field.label}（${field.goalTitle}）' : field.label,
        style: TextStyle(fontSize: 13, color: c.textSecondary),
      ),
      subtitle: Text(
        current == null ? next : '$current → $next（上書き）',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: c.textPrimary,
        ),
      ),
    );
  }
}
