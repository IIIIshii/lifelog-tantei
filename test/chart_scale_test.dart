import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nikkinext/core/chart_scale.dart';

// 数値の推移グラフの縦軸を検証する。
//
// ここを固める理由:
// 軸の決め方を間違えてもグラフは“それらしく”描かれてしまう。体重のように
// 変化の幅が小さい項目では、潰れた軸を目で見分けるのが難しい。
// 「幅0にしない」「目標線を範囲に含める」「刻みを丸める」の3点を機械で押さえる。
void main() {
  group('numericChartScale', () {
    test('値の範囲に余白を付けて返す', () {
      final scale = numericChartScale(const [60.0, 65.0]);
      expect(scale.minY, lessThan(60));
      expect(scale.maxY, greaterThan(65));
    });

    test('値が1件でも高さ0の帯にしない（線が枠と重なって見えなくなる）', () {
      final scale = numericChartScale(const [62.0]);
      expect(scale.maxY, greaterThan(scale.minY));
    });

    test('全部同じ値でも幅を持つ', () {
      final scale = numericChartScale(const [62.0, 62.0, 62.0]);
      expect(scale.maxY, greaterThan(scale.minY));
      expect(scale.minY, lessThan(62));
      expect(scale.maxY, greaterThan(62));
    });

    test('0 だけの記録でも幅を持つ（0.1倍では広がらないケース）', () {
      final scale = numericChartScale(const [0.0]);
      expect(scale.maxY, greaterThan(scale.minY));
    });

    test('記録が全部非負なら軸を負へ伸ばさない', () {
      final scale = numericChartScale(const [1.0, 2.0]);
      expect(scale.minY, greaterThanOrEqualTo(0));
    });

    test('負の記録があれば軸も負へ伸ばす', () {
      final scale = numericChartScale(const [-5.0, 5.0]);
      expect(scale.minY, lessThan(0));
    });

    test('目標値が範囲の外にあっても軸に含める（目標線が画面外に出ない）', () {
      final scale = numericChartScale(const [70.0, 71.0], target: 62);
      expect(scale.minY, lessThanOrEqualTo(62));
      expect(scale.maxY, greaterThanOrEqualTo(71));
    });

    test('目標が上にある場合も含める', () {
      final scale = numericChartScale(const [3000.0, 4000.0], target: 8000);
      expect(scale.maxY, greaterThanOrEqualTo(8000));
    });

    test('記録が無ければ安全な既定値を返す（描画を壊さない）', () {
      final scale = numericChartScale(const []);
      expect(scale.minY, 0);
      expect(scale.maxY, greaterThan(0));
      expect(scale.interval, greaterThan(0));
    });

    test('刻みは 1/2/5 × 10^n に丸まる（軸が小数の羅列にならない）', () {
      // 許容値を列挙せず式で判定する。桁が上がるたびに列挙漏れで
      // テストだけが落ちる（実装は正しいのに）のを避けるため。
      bool isNiceStep(double step) {
        for (var exponent = -3; exponent <= 6; exponent++) {
          final magnitude = math.pow(10, exponent).toDouble();
          for (final base in const [1.0, 2.0, 5.0]) {
            if ((step - base * magnitude).abs() < 1e-9) return true;
          }
        }
        return false;
      }

      for (final values in const [
        [60.0, 65.0],
        [3000.0, 9000.0],
        [0.5, 1.2],
        [62.0, 62.4],
        [8000.0, 12000.0],
      ]) {
        final scale = numericChartScale(values);
        expect(
          isNiceStep(scale.interval),
          isTrue,
          reason: '$values の刻みが丸まっていない: ${scale.interval}',
        );
      }
    });

    test('刻みは常に正（0 で割る描画を作らない）', () {
      expect(numericChartScale(const [5.0]).interval, greaterThan(0));
      expect(numericChartScale(const [0.0, 0.0]).interval, greaterThan(0));
    });
  });
}
