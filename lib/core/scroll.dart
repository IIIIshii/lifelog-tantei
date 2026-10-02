import 'package:flutter/material.dart';

// 会話画面を最下端へ追従させるヘルパ。
//
// なぜ2段構えなのか：
// 吹き出しを足した直後の1フレームでは、追加した分の高さが
// maxScrollExtent にまだ反映されていないことがある。1段（post-frame 1回）だけで
// animateTo すると、伸びる前の終端まで送られて最後の発言が画面外に残る。
// 2フレーム目に「まだ終端に届いていなければもう一度送る」を入れて追いつかせる。
//
// DiaryPage が private メソッドとして持っていたものをここへ出した。
// 相談室（ConsultPage）は1段の弱い版を持っていて同じ取りこぼしが起きるので、
// 会話を出す画面はこれを共有する。
void scrollToBottom(ScrollController controller) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!controller.hasClients) return;
    controller.animateTo(
      controller.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!controller.hasClients) return;
      final max = controller.position.maxScrollExtent;
      if (controller.offset < max) {
        controller.animateTo(
          max,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  });
}
