// 自由記述の回答から数値を取り出す純粋関数。
//
// なぜ純粋関数として切り出すか：
// 数値の記録項目には「62」「62.5kg」「約62キロ」「６２」のように、
// 同じ値がいくらでも違う書き方で入ってくる。とくに日本語IMEを通すと全角数字が普通に混じり、
// 正規表現の \d はこれにマッチしない。取りこぼしても回答文字列は保存されるので画面上は
// 正常に見え、分析室のグラフからだけ静かに値が消える ―― 目で気づけない種類の欠落なので、
// UIから独立させて単体テストで固めておく。
//
// 日々の記録の数値欄（daily_record.dart の normalizeInput）もこれで読む。

/// 全角数字（０-９）と全角ピリオド（．）を半角へ寄せる。
String _normalizeDigits(String text) {
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    if (rune >= 0xFF10 && rune <= 0xFF19) {
      // '０'..'９' → '0'..'9'
      buffer.writeCharCode(rune - 0xFF10 + 0x30);
    } else if (rune == 0xFF0E) {
      // '．' → '.'
      buffer.write('.');
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}

/// 自由記述から数値をひとつ取り出す。取れなければ null。
///
/// 最初に現れた数字列だけを見る（「62kg（朝）」「約62キロ」→ 62.0）。
/// 符号は解釈しない ―― 体重・歩数・時間・回数といった記録対象はいずれも非負で、
/// 「体重-62kg」のような書き方を負値と読むほうが誤りに繋がるため。
double? parseNumericAnswer(String text) {
  // 桁区切りのカンマ（1,062）は数字の一部として扱いたいので先に落とす
  final normalized = _normalizeDigits(text).replaceAll(',', '');
  final match = RegExp(r'\d+(?:\.\d+)?').firstMatch(normalized);
  if (match == null) return null;
  return double.tryParse(match.group(0)!);
}
