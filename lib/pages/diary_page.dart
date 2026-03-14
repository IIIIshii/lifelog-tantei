import 'package:flutter/material.dart';
import '../controllers/diary_session_controller.dart';
import '../core/theme/detective_theme.dart';
import '../widgets/message_bubble.dart';
import '../widgets/diary_card.dart';
import '../widgets/input_area.dart';
import 'diary_list_page.dart';

// 今日の日記を作成するページ。ビジネスロジックは DiarySessionController に委譲する
class DiaryPage extends StatefulWidget {
  const DiaryPage({super.key});

  @override
  State<DiaryPage> createState() => _DiaryPageState();
}

class _DiaryPageState extends State<DiaryPage> {
  late final DiarySessionController _controller;
  final TextEditingController _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = DiarySessionController();
    _controller.addListener(_onControllerUpdate);
    _controller.initialize();
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerUpdate);
    _controller.dispose();
    _textController.dispose();
    super.dispose();
  }

  // コントローラの状態変化を受けてUIを再描画し、エラーがあればダイアログを表示する
  void _onControllerUpdate() {
    if (!mounted) return;
    if (_controller.lastError != null) {
      _showError(_controller.lastError!);
      _controller.clearError();
    }
    setState(() {});
  }

  void _showError(String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('エラー'),
        content: SelectableText(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DetectiveTheme.background,

      // ── AppBar ──────────────────────────────────────────────
      appBar: AppBar(
        backgroundColor: DetectiveTheme.appBarBg,
        foregroundColor: const Color(0xFFE8DCC8),
        elevation: 0,
        toolbarHeight: 64,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('新規捜査', style: DetectiveTheme.appBarTitle),
            const SizedBox(height: 2),
            const Text('― 証拠を集める ―',
                style: DetectiveTheme.appBarSubtitle),
          ],
        ),
        actions: [
          // 事件簿アーカイブへのショートカットボタン
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: '事件簿アーカイブ',
            onPressed: () {
              if (_controller.uid == null) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DiaryListPage(uid: _controller.uid!),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _controller.messages.length +
                  (_controller.diary != null ? 1 : 0),
              itemBuilder: (context, index) {
                // 末尾に生成された日記カードを表示する
                if (_controller.diary != null &&
                    index == _controller.messages.length) {
                  return DiaryCard(diary: _controller.diary!);
                }
                final msg = _controller.messages[index];
                return MessageBubble(role: msg['role']!, text: msg['text']!);
              },
            ),
          ),
          if (_controller.isLoading)
            const Padding(
              padding: EdgeInsets.all(12.0),
              child: CircularProgressIndicator(color: DetectiveTheme.gold),
            ),
          // 追記 or 確認の選択肢ボタン
          if (_controller.showExistingDiaryChoice && !_controller.isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: ['追記する', '日記を確認する'].map((choice) {
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ElevatedButton(
                        onPressed: () =>
                            _controller.handleExistingDiaryChoice(choice),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF5C3D2E),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: Text(choice),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          // 選択肢ボタン群
          if (!_controller.showExistingDiaryChoice && _controller.showChoices)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _controller.currentChoices!.map((choice) {
                  return ElevatedButton(
                    onPressed: () => _controller.sendUserReply(choice),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: DetectiveTheme.gold,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: Text(choice),
                  );
                }).toList(),
              ),
            ),
          // 「これでいいですか？」確認ボタン
          if (_controller.showConfirmButton)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _controller.generateDiary,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DetectiveTheme.gold,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: const Text(
                    '事件簿を作成する',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          if (!_controller.showExistingDiaryChoice && _controller.showInput)
            InputArea(
              controller: _textController,
              onSubmit: (text) {
                _textController.clear();
                _controller.sendUserReply(text);
              },
            ),
        ],
      ),
    );
  }
}
