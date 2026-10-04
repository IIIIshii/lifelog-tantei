// 事件簿アーカイブの本棚に並べる「1か月分の本」の集計結果
class ArchiveMonth {
  final int year;
  final int month; // 1–12
  final int count; // その月の日記の件数

  const ArchiveMonth({
    required this.year,
    required this.month,
    required this.count,
  });
}

final _datePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

// 日付キー（YYYY-MM-DD）が実在する日付か検証し、不正なら FormatException を投げる。
//
// DateTime は存在しない日付（2月30日など）を翌月にずらして受け入れてしまうため、
// 生成した日付の年月日が入力と一致するかで実在を判定する。
// うるう年（2月29日の有無）は DateTime の暦に任せ、自前の判定は持たない。
void _validateDateKey(String raw) {
  final match = _datePattern.firstMatch(raw);
  if (match == null) {
    throw FormatException('日付キーが YYYY-MM-DD 形式ではありません', raw);
  }
  final y = int.parse(match.group(1)!);
  final m = int.parse(match.group(2)!);
  final d = int.parse(match.group(3)!);
  final parsed = DateTime(y, m, d);
  if (parsed.year != y || parsed.month != m || parsed.day != d) {
    throw FormatException('存在しない日付です', raw);
  }
}

// 日付（YYYY-MM-DD）→日記本文のマップを、月ごとの件数に集計して新しい月順で返す。
// 不正な日付キーが1つでもあれば FormatException を投げる（黙って捨てると
// 本棚から日記が消えたことに気づけないため）。
List<ArchiveMonth> groupByMonth(Map<String, String> entries) {
  final counts = <String, int>{}; // キーは 'YYYY-MM'
  for (final date in entries.keys) {
    _validateDateKey(date);
    final yearMonth = date.substring(0, 7);
    counts[yearMonth] = (counts[yearMonth] ?? 0) + 1;
  }

  // ゼロ埋めの 'YYYY-MM' なので、文字列の降順がそのまま新しい月順になる
  final keys = counts.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final key in keys)
      ArchiveMonth(
        year: int.parse(key.substring(0, 4)),
        month: int.parse(key.substring(5, 7)),
        count: counts[key]!,
      ),
  ];
}
