// 端末のタイムゾーン名から、通知の時刻計算に使う Location を引き当てる純粋関数。
//
// なぜ純粋関数として切り出すか：
// 端末は 'GMT' のように、timezone パッケージの一覧に無い名前を返すことがある
// （一覧にあるのは 'Etc/GMT'）。引き当てに失敗した例外が起動処理から抜けると、
// 通知という補助機能のせいでアプリ全体が白い画面で止まる。
// 失敗してもアプリを起動させる、という判断をここに閉じ込めておけば、端末なしでテストできる。
//
// 呼び出す前に tz.initializeTimeZones() を済ませておくこと。

import 'package:timezone/timezone.dart' as tz;

/// 引き当てに失敗したときに使うタイムゾーン名。
///
/// 日本向けのアプリで、使う人の大半は日本にいるため。
/// 端末が本当に別の地域にある場合、通知の時刻はその分ずれる。
const fallbackTimeZoneName = 'Asia/Tokyo';

/// タイムゾーン名から Location を返す。名前が null・空・一覧に無いときは
/// [fallbackTimeZoneName] の Location を返す（例外は投げない）。
tz.Location resolveLocation(String? name) {
  if (name != null && name.isNotEmpty) {
    try {
      return tz.getLocation(name);
    } on tz.LocationNotFoundException {
      // 下のフォールバックに落とす
    }
  }
  return tz.getLocation(fallbackTimeZoneName);
}
