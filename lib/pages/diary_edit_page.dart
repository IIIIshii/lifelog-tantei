import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/detective_text_styles.dart';
import '../services/firestore_service.dart';

// テキスト入力で日記を書く・編集するページ。
// initialDiary が null のときは新規入力、非null のときは編集モード。
//
// 保存したら pop(true) で戻る。呼び出し側（聴取・詳細画面）はそれを見て
// 画面を閉じるか、本文を読み直すかを決める。
class DiaryEditPage extends StatefulWidget {
  final String uid;

  /// 対象の日付（YYYY-MM-DD）
  final String date;
  final FirestoreService firestore;
  final String? initialDiary;

  const DiaryEditPage({
    super.key,
    required this.uid,
    required this.date,
    required this.firestore,
    this.initialDiary,
  });

  @override
  State<DiaryEditPage> createState() => _DiaryEditPageState();
}

class _DiaryEditPageState extends State<DiaryEditPage> {
  late final TextEditingController _controller;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialDiary ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _isSaving = true);
    try {
      await widget.firestore.saveDiary(
        widget.uid,
        widget.date,
        text: text,
        // 新しく書いたときだけ作り方を残す。聴取でまとめたものを直したときは
        // 出来事の記録（topics）と作り方をそのまま残す。
        mode: widget.initialDiary == null ? 'manual' : null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('事件簿に綴じておいた')));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('エラー'),
          content: Text('$e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initialDiary != null;
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
              isEdit ? '事件簿を編集' : '事件簿を入力',
              style: DetectiveTextStyles.appBarTitle(color: c.appBarFg),
            ),
            const SizedBox(height: 2),
            Text(
              isEdit ? '― 記録を修正する ―' : '― 自分で記録する ―',
              style: DetectiveTextStyles.appBarSubtitle(
                color: c.appBarSubtitle,
              ),
            ),
          ],
        ),
      ),
      body: _buildEditorView(isEdit, c),
    );
  }

  Widget _buildEditorView(bool isEdit, AppColors c) {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _controller,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: TextStyle(fontSize: 15, color: c.textPrimary, height: 1.7),
              decoration: InputDecoration(
                hintText: '今日の出来事を自由に記述してください…',
                hintStyle: TextStyle(color: c.textSecondary),
                filled: true,
                fillColor: c.cardBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: c.cardBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: c.gold, width: 1.5),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: c.gold,
                foregroundColor: c.onAccent,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              child: _isSaving
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: c.onAccent,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      isEdit ? '編集を保存する' : '日記を保存する',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
