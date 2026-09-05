import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'analytics_page.dart';
import 'diary_list_page.dart';
import 'diary_page.dart';
import 'home_page.dart';
import 'role_select_page.dart';
import 'settings_page.dart';

// ──────────────────────────────────────────────────────────────
// アプリのシェル。ボトムナビゲーションで5つのタブを束ねる。
//
// なぜハブ＆スポーク（ホームからの Navigator.push）をやめるのか：
// 頻繁に行き来する「記録・事件簿・分析」を切り替えるたびにホームへ戻る必要があり、
// タップ対象も画面上部に集中していた。Material 3 は compact サイズでは
// ボトムナビゲーションを推奨しており（Drawer が非推奨な理由も、上部に手を伸ばす
// 必要があること）、主要動線を親指の届く画面下部へ移す。
//
// destination は5つ。Material 3 / Apple HIG ともに 3〜5 が推奨範囲で、その上限。
// ──────────────────────────────────────────────────────────────
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  static const int _homeIndex = 0;
  static const int _roleIndex = 3;
  static const int _tabCount = 5;

  late final String _uid;

  int _index = _homeIndex;

  // 一度でも開いたタブの index。
  // AnalyticsPage / SettingsPage は initState で Firestore を読むため、
  // 素の IndexedStack だと起動時に5画面ぶん一斉にフェッチしてしまう。
  // 未訪問のタブには空ウィジェットを置き、初回表示まで生成を遅らせる。
  final Set<int> _visited = {_homeIndex};

  // ホームの再読込シグナル。
  // IndexedStack はページを破棄しないので、他タブでの変更（探偵の指名、
  // デモデータ投入など）をホームに反映するには明示的な合図が要る。
  final ValueNotifier<int> _homeRefresh = ValueNotifier<int>(0);

  // 今日の記録有無。HomePage が読み込み結果を書き込み、FAB のラベルに反映する。
  final ValueNotifier<bool?> _todayDone = ValueNotifier<bool?>(null);

  @override
  void initState() {
    super.initState();
    // AuthGate により認証済みでのみ表示されるため uid は非 null を前提とする
    _uid = FirebaseAuth.instance.currentUser!.uid;
  }

  @override
  void dispose() {
    _homeRefresh.dispose();
    _todayDone.dispose();
    super.dispose();
  }

  void _bumpHomeRefresh() => _homeRefresh.value++;

  void _selectTab(int i) {
    setState(() {
      _index = i;
      _visited.add(i);
    });
    // 事務所タブに戻ってきたタイミングで最新の状態を取り直す
    if (i == _homeIndex) _bumpHomeRefresh();
  }

  // 主要動線。記録が終わって戻ってきたらホームを更新する。
  void _openDiary() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const DiaryPage()),
    ).then((_) => _bumpHomeRefresh());
  }

  Widget _buildTab(int i) {
    switch (i) {
      case 0:
        return HomePage(
          uid: _uid,
          refreshSignal: _homeRefresh,
          todayDone: _todayDone,
          onOpenRoleTab: () => _selectTab(_roleIndex),
        );
      case 1:
        return DiaryListPage(uid: _uid);
      case 2:
        return const AnalyticsPage();
      case 3:
        return const RoleSelectPage();
      default:
        return const SettingsPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 各タブページは自前の Scaffold と AppBar を持つ。シェルがルート
      // （AuthGate の直下）なので Navigator.canPop が false になり、
      // AppBar の戻る矢印は自動的に出ない。既存ページの改修は不要。
      body: IndexedStack(
        index: _index,
        children: [
          for (var i = 0; i < _tabCount; i++)
            _visited.contains(i) ? _buildTab(i) : const SizedBox.shrink(),
        ],
      ),

      // ── 主要動線（Extended FAB） ────────────────────────────
      // 画面の primary action は1画面につき1つ。ラベル付きにすることで
      // 何が起きるかが明示され、タップ面積も広く取れる。事務所タブでのみ出す。
      floatingActionButton: _index == _homeIndex
          ? ValueListenableBuilder<bool?>(
              valueListenable: _todayDone,
              builder: (context, done, _) => FloatingActionButton.extended(
                onPressed: _openDiary,
                icon: const Icon(Icons.edit_note),
                label: Text(done == true ? '捜査を続ける' : '捜査を開始する'),
              ),
            )
          : null,

      // ── ボトムナビゲーション ────────────────────────────────
      // 色は AppBar と同じインク色（navigationBarTheme で指定）。
      // 構造は Material 3 標準のまま、世界観はラベルの語彙と色だけで出す。
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '事務所',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: '事件簿',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: '分析室',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_search_outlined),
            selectedIcon: Icon(Icons.person_search),
            label: '探偵',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '設定',
          ),
        ],
      ),
    );
  }
}
