import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nikkinext/widgets/typewriter_text.dart';

// Stack内に寸法確保用の非表示Textが常駐しているため、実際に「見えている」
// 文字列は最後に積まれたTextから取り出す。
String visibleText(WidgetTester tester) {
  final texts = tester.widgetList<Text>(find.byType(Text)).toList();
  return texts.last.data ?? '';
}

void main() {
  testWidgets('タイプが進むと全文が表示され onFinished が呼ばれる', (tester) async {
    var finished = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TypewriterText(
            text: 'あいうえお',
            speed: const Duration(milliseconds: 10),
            onFinished: () => finished++,
          ),
        ),
      ),
    );

    // 開始直後は途中までしか出ていない
    await tester.pump(const Duration(milliseconds: 10));
    expect(visibleText(tester).length, lessThan(5));
    expect(finished, 0);

    await tester.pumpAndSettle();
    expect(visibleText(tester), 'あいうえお');
    expect(finished, 1);
  });

  testWidgets('text を差し替えると新しい文章に作り直される', (tester) async {
    Widget build(String text) => MaterialApp(
      home: Scaffold(
        body: TypewriterText(
          text: text,
          speed: const Duration(milliseconds: 10),
        ),
      ),
    );

    await tester.pumpWidget(build('前の発言'));
    await tester.pumpAndSettle();
    expect(visibleText(tester), '前の発言');

    // 同じ位置のElementが使い回されるケース。didUpdateWidgetが無いと
    // ここで「前の発言」が残り続ける。
    await tester.pumpWidget(build('次の発言'));
    await tester.pumpAndSettle();
    expect(visibleText(tester), '次の発言');
    expect(find.text('前の発言'), findsNothing);
  });

  testWidgets('タップすると残りが一気に表示される', (tester) async {
    var finished = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TypewriterText(
            text: '長い長い証言テキスト',
            speed: const Duration(milliseconds: 100),
            onFinished: () => finished++,
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 100));
    expect(visibleText(tester).length, lessThan(10));

    await tester.tap(find.byType(TypewriterText));
    await tester.pump();
    expect(visibleText(tester), '長い長い証言テキスト');
    expect(finished, 1);

    // 完了後に再度タップしても二重に通知されない
    await tester.tap(find.byType(TypewriterText));
    await tester.pumpAndSettle();
    expect(finished, 1);
  });

  testWidgets('絵文字を含む文章が途中で分断されない', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TypewriterText(
            text: '今日は👨‍👩‍👧‍👦と会った',
            speed: const Duration(milliseconds: 10),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(visibleText(tester), '今日は👨‍👩‍👧‍👦と会った');
  });
}
