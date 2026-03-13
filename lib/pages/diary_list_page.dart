import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../services/firestore_service.dart';
import 'diary_detail_page.dart';

class DiaryListPage extends StatefulWidget {
  final String uid;

  const DiaryListPage({super.key, required this.uid});

  @override
  State<DiaryListPage> createState() => _DiaryListPageState();
}

class _DiaryListPageState extends State<DiaryListPage> {
  /// date string (YYYY-MM-DD) → diary text
  final Map<String, String> _entries = {};
  bool _isLoading = true;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  final FirestoreService _firestore = FirestoreService();

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    // 過去365日分のエントリを取得
    final history =
        await _firestore.getStatsHistory(widget.uid, days: 365);
    final map = <String, String>{};
    for (final e in history) {
      final diary = e['diary'] as String?;
      if (diary != null) {
        map[e['date'] as String] = diary;
      }
    }
    setState(() {
      _entries.addAll(map);
      _isLoading = false;
    });
  }

  bool _hasDiary(DateTime day) {
    return _entries.containsKey(_dateKey(day));
  }

  String _dateKey(DateTime day) {
    return '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final selectedKey =
        _selectedDay != null ? _dateKey(_selectedDay!) : null;
    final selectedDiary =
        selectedKey != null ? _entries[selectedKey] : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('日記の記録'),
        backgroundColor: const Color(0xFF2E5C45),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF5F0EB),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildCalendar(),
                const Divider(height: 1),
                Expanded(
                  child: _buildSelectedDiary(
                      selectedKey, selectedDiary),
                ),
              ],
            ),
    );
  }

  Widget _buildCalendar() {
    return TableCalendar(
      firstDay: DateTime.utc(2020, 1, 1),
      lastDay: DateTime.utc(2100, 12, 31),
      focusedDay: _focusedDay,
      selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
      calendarFormat: CalendarFormat.month,
      availableCalendarFormats: const {CalendarFormat.month: '月'},
      locale: 'ja_JP',
      headerStyle: const HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
        titleTextStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Color(0xFF1A1A1A),
        ),
      ),
      calendarStyle: const CalendarStyle(
        todayDecoration: BoxDecoration(
          color: Color(0xFFB5956A),
          shape: BoxShape.circle,
        ),
        selectedDecoration: BoxDecoration(
          color: Color(0xFF5C3D2E),
          shape: BoxShape.circle,
        ),
        markerDecoration: BoxDecoration(
          color: Color(0xFF2E5C45),
          shape: BoxShape.circle,
        ),
        markersMaxCount: 1,
      ),
      eventLoader: (day) => _hasDiary(day) ? [true] : [],
      onDaySelected: (selectedDay, focusedDay) {
        setState(() {
          _selectedDay = selectedDay;
          _focusedDay = focusedDay;
        });
      },
      onPageChanged: (focusedDay) {
        setState(() => _focusedDay = focusedDay);
      },
    );
  }

  Widget _buildSelectedDiary(String? dateKey, String? diary) {
    if (_selectedDay == null) {
      return Center(
        child: Text(
          '日付を選択すると日記を確認できます',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
        ),
      );
    }

    final label =
        '${_selectedDay!.year}年${_selectedDay!.month}月${_selectedDay!.day}日';

    if (diary == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit_off, size: 40, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF7A5C4A)),
            ),
            const SizedBox(height: 4),
            Text(
              'この日の記録はありません',
              style:
                  TextStyle(color: Colors.grey.shade500, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              DiaryDetailPage(date: dateKey!, diary: diary),
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF5C3D2E),
                  ),
                ),
                const Spacer(),
                const Text(
                  'タップで全文表示 →',
                  style:
                      TextStyle(fontSize: 11, color: Color(0xFF7A5C4A)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  diary,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, height: 1.8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
