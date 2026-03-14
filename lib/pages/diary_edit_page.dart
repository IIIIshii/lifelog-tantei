import 'package:flutter/material.dart';
import '../core/theme/detective_theme.dart';
import '../services/firestore_service.dart';
import 'diary_list_page.dart';

// テキスト入力で日記を書く・編集するページ
// initialDiary が null のときは新規入力、非null のときは編集モード
class DiaryEditPage extends StatefulWidget {
  final String uid;
  final String today;
  final FirestoreService firestore;
  final String? initialDiary;

  const DiaryEditPage({
    super.key,
    required this.uid,
    required this.today,
    required this.firestore,
    this.initialDiary,
  });

  @override
  State<DiaryEditPage> createState() => _DiaryEditPageState();
}

class _DiaryEditPageState extends State<DiaryEditPage> {
  late final TextEditingController _controller;
  bool _isSaving = false;
  bool _saved = false;

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
      await widget.firestore.saveDiary(widget.uid, widget.today, text);
      setState(() => _saved = true);
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('エラー'),
            content: Text('$e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initialDiary != null;

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
            Text(isEdit ? '事件簿を編集' : '事件簿を入力',
                style: DetectiveTheme.appBarTitle),
            const SizedBox(height: 2),
            Text(isEdit ? '― 記録を修正する ―' : '― 自分で記録する ―',
                style: DetectiveTheme.appBarSubtitle),
          ],
        ),
      ),
      body: _saved ? _buildSavedView() : _buildEditorView(isEdit),
    );
  }

  // 保存完了後の画面
  Widget _buildSavedView() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_outline,
              color: DetectiveTheme.gold, size: 64),
          const SizedBox(height: 16),
          const Text(
            'お疲れ様でした。\n記録した日記は事件簿アーカイブから確認できます。',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 16, color: DetectiveTheme.textPrimary, height: 1.6),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      Navigator.popUntil(context, (r) => r.isFirst),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: DetectiveTheme.gold,
                    side: const BorderSide(color: DetectiveTheme.gold),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                  ),
                  child: const Text('ホームへ'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            DiaryListPage(uid: widget.uid),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DetectiveTheme.gold,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                  ),
                  child: const Text('事件簿アーカイブへ'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // テキスト編集画面
  Widget _buildEditorView(bool isEdit) {
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
              style: const TextStyle(
                  fontSize: 15,
                  color: DetectiveTheme.textPrimary,
                  height: 1.7),
              decoration: InputDecoration(
                hintText: '今日の出来事を自由に記述してください…',
                hintStyle: TextStyle(
                    color: DetectiveTheme.textSecondary.withValues(alpha: 0.6)),
                filled: true,
                fillColor: DetectiveTheme.cardBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: DetectiveTheme.cardBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: DetectiveTheme.gold, width: 1.5),
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
                backgroundColor: DetectiveTheme.gold,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4)),
              ),
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : Text(isEdit ? '編集を保存する' : '日記を保存する',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ],
    );
  }
}
