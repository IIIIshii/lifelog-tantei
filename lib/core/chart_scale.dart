import 'dart:math' as math;

// 数値の推移グラフの縦軸を決める純粋関数。
//
// なぜ純粋関数として切り出すか：
// 目盛りの決め方は「値が1件でも高さ0の帯にしない」「0起点に丸めない」
// 「刻みが小数の羅列にならないよう丸める」といった判断の積み上げで、
// 取り違えてもグラフは“それらしく”描かれてしまう。体重のように変化の幅が
// 小さい項目では、軸が潰れていても目では気づけない。
//
// 睡眠用の _SleepChart（analytics_page）は maxY を 12 に固定しているが、
// 目標の数値項目は体重・歩数・分数と桁がまるで違うので値から決めるほかない。

/// 数値の並びから縦軸の範囲と刻みを決める。
///
/// target（目標値）があれば範囲に含める ―― 目標線がグラフの外に出ると、
/// 「あとどれだけか」を読み取れなくなる。
///
/// 0 起点には丸めない。体重のように「差」を見る項目では、0 から描くと
/// 変化が下端の一本に潰れてしまう。ただし記録が全部非負なら軸を負へは伸ばさない
/// （起こらない範囲が場所を取るだけになる）。
({double minY, double maxY, double interval}) numericChartScale(
  Iterable<double> values, {
  double? target,
}) {
  final points = [...values];
  if (target != null) points.add(target);
  if (points.isEmpty) return (minY: 0, maxY: 1, interval: 1);

  var lo = points.first;
  var hi = points.first;
  for (final value in points) {
    if (value < lo) lo = value;
    if (value > hi) hi = value;
  }

  if (hi == lo) {
    // 全部同じ値でも高さ0にしない（線が枠と重なって見えなくなる）
    final span = hi.abs() < 1 ? 1.0 : hi.abs() * 0.1;
    lo -= span;
    hi += span;
  } else {
    final pad = (hi - lo) * 0.1;
    lo -= pad;
    hi += pad;
  }

  if (lo < 0 && points.every((value) => value >= 0)) lo = 0;

  return (minY: lo, maxY: hi, interval: _niceInterval(hi - lo));
}

// 軸ラベルの刻み。目盛りが4本前後に収まる値を 1/2/5×10^n から選ぶ。
// 生の (max-min)/4 をそのまま使うと 0.7333… のような刻みになり軸が読めない。
double _niceInterval(double span) {
  if (span <= 0) return 1;
  final raw = span / 4;
  final magnitude = math
      .pow(10, (math.log(raw) / math.ln10).floor())
      .toDouble();
  final normalized = raw / magnitude;
  final step = normalized <= 1
      ? 1.0
      : normalized <= 2
      ? 2.0
      : normalized <= 5
      ? 5.0
      : 10.0;
  return step * magnitude;
}
