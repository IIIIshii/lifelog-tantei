import 'package:flutter_test/flutter_test.dart';
import 'package:nikkinext/core/numeric_answer.dart';

// 自由記述から数値を拾う処理を検証する。
//
// ここを固める理由:
// 数値を取りこぼしても回答文字列そのものは保存されるため、画面上は正常に見えて
// 分析室のグラフからだけ値が消える。目視では気づけない欠落なので機械で確かめる。
// とくに全角数字は日本語IMEから普通に入ってくるのに、正規表現の \d にはマッチしない。
void main() {
  group('parseNumericAnswer', () {
    test('素の数字を読む', () {
      expect(parseNumericAnswer('62'), 62.0);
      expect(parseNumericAnswer('62.5'), 62.5);
      expect(parseNumericAnswer('0'), 0.0);
    });

    test('単位や前置きが付いていても読む', () {
      expect(parseNumericAnswer('62kg'), 62.0);
      expect(parseNumericAnswer('62 kg'), 62.0);
      expect(parseNumericAnswer('約62キロ'), 62.0);
      expect(parseNumericAnswer('62.5kgだった'), 62.5);
      expect(parseNumericAnswer('  7  '), 7.0);
    });

    test('全角数字も読む（日本語IMEから普通に入ってくる）', () {
      expect(parseNumericAnswer('６２'), 62.0);
      expect(parseNumericAnswer('６２．５'), 62.5);
      expect(parseNumericAnswer('６２ｋｇ'), 62.0);
    });

    test('桁区切りのカンマを落として読む', () {
      expect(parseNumericAnswer('1,062'), 1062.0);
      expect(parseNumericAnswer('8,500歩'), 8500.0);
    });

    test('数字が無ければ null', () {
      expect(parseNumericAnswer(''), isNull);
      expect(parseNumericAnswer('測ってない'), isNull);
      expect(parseNumericAnswer('kg'), isNull);
      expect(parseNumericAnswer('—'), isNull);
    });

    test('最初の数字列だけを見る', () {
      expect(parseNumericAnswer('62kgから61kgへ'), 62.0);
    });

    test('符号は解釈しない（記録対象はいずれも非負）', () {
      expect(parseNumericAnswer('-3'), 3.0);
    });
  });
}
