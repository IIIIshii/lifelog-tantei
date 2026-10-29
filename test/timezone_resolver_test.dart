import 'package:flutter_test/flutter_test.dart';
import 'package:nikkinext/core/timezone_resolver.dart';
import 'package:timezone/data/latest.dart' as tz;

void main() {
  setUpAll(tz.initializeTimeZones);

  group('resolveLocation', () {
    test('一覧にある名前はその地域を返す', () {
      expect(resolveLocation('America/New_York').name, 'America/New_York');
    });

    test("端末が返す 'GMT' は一覧に無いので、フォールバックを返す（issue #193）", () {
      expect(resolveLocation('GMT').name, fallbackTimeZoneName);
    });

    test('でたらめな名前でも例外を投げず、フォールバックを返す', () {
      expect(resolveLocation('Not/AZone').name, fallbackTimeZoneName);
    });

    test('空文字・null はフォールバックを返す', () {
      expect(resolveLocation('').name, fallbackTimeZoneName);
      expect(resolveLocation(null).name, fallbackTimeZoneName);
    });

    test('フォールバックは日本標準時（UTC+9）', () {
      final offset = resolveLocation('GMT').currentTimeZone.offset;
      expect(offset, const Duration(hours: 9));
    });
  });
}
