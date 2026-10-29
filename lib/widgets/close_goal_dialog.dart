import 'package:flutter/material.dart';

import '../models/goal.dart';

// 追跡を終えるときの確認ダイアログ。終えた理由を一言残せる。
//
// 理由は利用者に書かせず、AI が先に作った下書きを欄へ入れる（draft）。
// 合っていればそのまま閉じるだけでよく、違っていれば直す。
// 下書きは待たせない：ダイアログは先に開き、できたら欄に入れる。
// ただし利用者が先に書き始めていたら、その入力を上書きしない。
//
// 戻り値は、確定したときの理由（空でもよい）。キャンセルは null。
class CloseGoalDialog extends StatefulWidget {
  final Goal goal;
  final bool solved;
  final Future<String> draft;

  const CloseGoalDialog({
    super.key,
    required this.goal,
    required this.solved,
    required this.draft,
  });

  @override
  State<CloseGoalDialog> createState() => _CloseGoalDialogState();
}

class _CloseGoalDialogState extends State<CloseGoalDialog> {
  final _controller = TextEditingController();
  bool _drafting = true; // 下書きを待っているか
  bool _edited = false; // 利用者が欄に触ったか
  bool _fromDraft = false; // 欄の中身が AI の下書きのままか

  @override
  void initState() {
    super.initState();
    widget.draft.then((text) {
      if (!mounted) return;
      setState(() {
        _drafting = false;
        if (!_edited && text.isNotEmpty) {
          _controller.text = text;
          _fromDraft = true;
        }
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final solved = widget.solved;
    return AlertDialog(
      title: Text(solved ? '事件を解決済みにするか？' : 'この事件の追跡をやめるか？'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              solved
                  ? '「${widget.goal.title}」を解決済みとして記録する。'
                        '日々の記録からこの事件の項目が外れる。これまでの記録は残る。'
                  : '「${widget.goal.title}」を解決済みの事件へ移す。'
                        '日々の記録から項目が外れるだけで、これまでの記録は残る。',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              maxLines: 3,
              minLines: 2,
              onChanged: (_) => setState(() {
                _edited = true;
                _fromDraft = false;
              }),
              decoration: InputDecoration(
                labelText: '理由（あとで読み返すメモ。空でもよい）',
                helperText: _drafting
                    ? '下書きを作っている…'
                    : (_fromDraft ? 'AIの下書き。違っていたら直してください' : null),
                helperMaxLines: 2,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text(solved ? '解決にする' : '追跡をやめる'),
        ),
      ],
    );
  }
}
