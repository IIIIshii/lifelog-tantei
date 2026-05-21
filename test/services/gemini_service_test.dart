import 'package:flutter_test/flutter_test.dart';
import 'package:nikkinext/services/gemini_service.dart';

void main() {
  group('GeminiService.isDoneResponse', () {
    test('DONEの表記ゆれを終了判定できる', () {
      expect(GeminiService.isDoneResponse('DONE'), isTrue);
      expect(GeminiService.isDoneResponse('DONE。'), isTrue);
      expect(GeminiService.isDoneResponse('done'), isTrue);
      expect(GeminiService.isDoneResponse('  DONE\n'), isTrue);
    });

    test('DONEを含まない文字列は終了判定しない', () {
      expect(GeminiService.isDoneResponse('もう少し詳しく教えてください。'), isFalse);
      expect(GeminiService.isDoneResponse(''), isFalse);
      expect(GeminiService.isDoneResponse('ABANDONED'), isFalse);
    });
  });
}
