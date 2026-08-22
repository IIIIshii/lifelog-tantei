import 'package:flutter/material.dart';

/// テキストを1文字ずつ表示するタイプライター風ウィジェット。
///
/// なぜ外部パッケージを使わず自前実装するか：
/// この手のパッケージは「複数のテキストを順繰りに切り替えて繰り返す」ことが主目的で、
/// 本アプリの「1つの発言を1回だけタイプする」用途とは狙いがずれている。
/// 特に、表示中に text が差し替わったときの作り直しを想定していないものが多く、
/// ListView.builder が Element を使い回す場面で前の発言を表示し続けてしまう。
/// ここでは didUpdateWidget で明示的に作り直すことでその問題を避けている。
class TypewriterText extends StatefulWidget {
  /// 最終的に表示しきる全文。
  final String text;
  final TextStyle? style;

  /// 1文字あたりの表示間隔。
  final Duration speed;

  /// 全文を表示しきった時点で1度だけ呼ばれる。タップでスキップした場合も呼ばれる。
  final VoidCallback? onFinished;

  const TypewriterText({
    super.key,
    required this.text,
    this.style,
    this.speed = const Duration(milliseconds: 25),
    this.onFinished,
  });

  @override
  State<TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<TypewriterText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  /// 書記素クラスタ単位の文字数。絵文字や結合文字を途中で分断しないため
  /// String.length ではなく characters を使う。
  late int _charCount;

  @override
  void initState() {
    super.initState();
    _charCount = widget.text.characters.length;
    _controller = AnimationController(
      vsync: this,
      duration: widget.speed * _charCount,
    )..addStatusListener(_handleStatusChanged);
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant TypewriterText oldWidget) {
    super.didUpdateWidget(oldWidget);
    // ListView.builder は同じ位置の Element を使い回すため、text が差し替わっても
    // State はそのまま残る。ここで巻き戻さないと前の発言を表示し続けてしまう。
    // なお controller は作り直さない（SingleTickerProviderStateMixin は
    // Ticker を1つしか作れないため）。duration を差し替えて再生し直す。
    if (oldWidget.text != widget.text || oldWidget.speed != widget.speed) {
      _charCount = widget.text.characters.length;
      _controller.duration = widget.speed * _charCount;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed) widget.onFinished?.call();
  }

  /// タップで残りを一気に表示する。長文を最後まで待たされないための逃げ道。
  /// value に 1.0 を代入すると status が completed になり onFinished も発火する。
  void _skipToEnd() {
    if (_controller.isAnimating) _controller.value = 1.0;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      // 読み上げには途中経過ではなく全文を渡す
      label: widget.text,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _skipToEnd,
          child: Stack(
            children: [
              // 全文のサイズで領域を先に確保しておく。タイプ中に高さが変動すると
              // 呼び出し側のスクロール追従（DiaryPage の _scrollToBottom）が
              // 最下端に届かなくなるため。
              Opacity(
                opacity: 0,
                child: Text(widget.text, style: widget.style),
              ),
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  // ceil にすることで再生開始と同時に1文字目が出る
                  final visibleCount = (_controller.value * _charCount).ceil();
                  return Text(
                    widget.text.characters.take(visibleCount).toString(),
                    style: widget.style,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
