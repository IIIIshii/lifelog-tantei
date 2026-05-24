import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../services/speech_service.dart';

// ユーザーが証言（テキスト）を入力して送信するための入力エリアウィジェット
// 羊皮紙風の塗りつぶしフィールド＋マイクボタン＋ゴールドの丸い送信ボタンで証言台を表現する
class InputArea extends StatefulWidget {
  final TextEditingController controller;
  final void Function(String) onSubmit; // 送信時に呼ばれるコールバック

  const InputArea(
      {super.key, required this.controller, required this.onSubmit});

  @override
  State<InputArea> createState() => _InputAreaState();
}

class _InputAreaState extends State<InputArea> {
  bool _isListening = false;
  // 音声認識開始時点のテキスト。認識結果はこの末尾に追記する形で反映する
  String _baseText = '';

  @override
  void dispose() {
    if (_isListening) {
      SpeechService.instance.stopListening();
    }
    super.dispose();
  }

  Future<void> _toggleMic() async {
    final svc = SpeechService.instance;
    if (_isListening) {
      await svc.stopListening();
      if (mounted) setState(() => _isListening = false);
      return;
    }

    _baseText = widget.controller.text;
    final ok = await svc.startListening(
      onResult: (text) {
        // 既存テキスト末尾に認識結果を追記。カーソルを末尾に置いて編集しやすくする
        final newText =
            _baseText.isEmpty ? text : '$_baseText$text';
        widget.controller.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: newText.length),
        );
      },
      onDone: () {
        if (mounted) setState(() => _isListening = false);
      },
    );

    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('マイクの使用が許可されていません')),
        );
      }
      return;
    }
    if (mounted) setState(() => _isListening = true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      // 入力エリア全体に薄いトップボーダーを付けてチャット領域と区切る
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      decoration: BoxDecoration(
        color: c.cardBg,
        border: Border(top: BorderSide(color: c.cardBorder)),
      ),
      child: Row(
        children: [
          // ── テキストフィールド ──────────────────────────────
          // 塗りつぶしの羊皮紙背景でノワール感を演出する
          Expanded(
            child: TextField(
              controller: widget.controller,
              style: TextStyle(
                fontSize: 14,
                color: c.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: _isListening ? '聞き取り中...' : '証言を入力...',
                hintStyle: TextStyle(
                  color: c.textSecondary,
                  fontSize: 13,
                ),
                filled: true,
                fillColor: c.background,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                // 通常時: カードボーダー色
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: c.cardBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: c.cardBorder),
                ),
                // フォーカス時: ゴールドに変化させてアクティブ状態を示す
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: c.gold, width: 1.5),
                ),
              ),
              onSubmitted: widget.onSubmit, // キーボードのEnterキーでも送信できる
            ),
          ),

          const SizedBox(width: 8),

          // ── マイクボタン ────────────────────────────────────
          // タップで音声認識を開始/停止。録音中はアイコンと色を切り替える
          GestureDetector(
            onTap: _toggleMic,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _isListening ? Colors.redAccent : c.background,
                shape: BoxShape.circle,
                border: Border.all(color: c.cardBorder),
              ),
              child: Icon(
                _isListening ? Icons.mic : Icons.mic_none,
                color: _isListening ? Colors.white : c.textPrimary,
                size: 22,
              ),
            ),
          ),

          const SizedBox(width: 8),

          // ── 送信ボタン ─────────────────────────────────────
          // ゴールドの丸いボタンで探偵テーマに統一する
          GestureDetector(
            onTap: () => widget.onSubmit(widget.controller.text),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: c.gold,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.arrow_forward,
                  color: c.appBarFg, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
