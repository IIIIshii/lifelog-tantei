import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'activity_page.dart';
import 'diary_page.dart';
import 'diary_list_page.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _uid;
  final AuthService _auth = AuthService();

  @override
  void initState() {
    super.initState();
    _initUid();
  }

  Future<void> _initUid() async {
    final uid = await _auth.signInAnonymously();
    setState(() => _uid = uid);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F0EB),
      appBar: AppBar(
        title: const Text('ライフログ探偵'),
        backgroundColor: const Color(0xFF3D2B1F),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            const Text(
              '今日も記録してみましょう',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF7A5C4A),
              ),
            ),
            const SizedBox(height: 24),
            _MenuCard(
              icon: Icons.edit_note,
              title: '今日の日記',
              subtitle: '日記を書く・追記する',
              color: const Color(0xFF5C3D2E),
              onTap: _uid == null
                  ? null
                  : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DiaryPage(),
                        ),
                      ),
            ),
            const SizedBox(height: 16),
            _MenuCard(
              icon: Icons.menu_book,
              title: '日記の記録',
              subtitle: '過去の日記を見る',
              color: const Color(0xFF2E5C45),
              onTap: _uid == null
                  ? null
                  : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DiaryListPage(uid: _uid!),
                        ),
                      ),
            ),
            const SizedBox(height: 16),
            _MenuCard(
              icon: Icons.bar_chart,
              title: '活動の記録',
              subtitle: '習慣や行動をグラフで見る',
              color: const Color(0xFF2E4A5C),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ActivityPage()),
              ),
            ),
            const SizedBox(height: 16),
            _MenuCard(
              icon: Icons.settings,
              title: '設定',
              subtitle: '記録したい項目を設定する',
              color: const Color(0xFF4A4A5C),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              ),
            ),
          ],
        ),
      ),
    );
  }


}

class _MenuCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  const _MenuCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF888888),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              const Icon(Icons.chevron_right, color: Color(0xFFCCCCCC)),
            ],
          ),
        ),
      ),
    );
  }
}
