import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'analytics_page.dart';
import 'consult_hub_page.dart';
import 'diary_list_page.dart';
import 'diary_page.dart';
import 'goal_check_in_page.dart';
import 'home_page.dart';
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
// 枠が5つしか無いので、毎日は開かない「探偵の指名」は設定ページ配下の push へ戻し、
// 空いた枠を相談室（追跡中の事件のハブ）に充てている
// ―― 目標は毎日の記録の主題で、ホームからの push より行き来が多いため。
// ──────────────────────────────────────────────────────────────
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  static const int _homeIndex = 0;
  static const int _consultIndex = 2;
  static const int _settingsIndex = 4;
  static const int _tabCount = 5;

  late final String _uid;

  int _index = _homeIndex;

  // 一度でも開いたタブの index。
  // ConsultHubPage / AnalyticsPage / SettingsPage は initState で Firestore を読むため、
  // 素の IndexedStack だと起動時に5画面ぶん一斉にフェッチしてしまう。
  // 未訪問のタブには空ウィジェットを置き、初回表示まで生成を遅らせる。
  final Set<int> _visited = {_homeIndex};

  // ホームの再読込シグナル。
  // IndexedStack はページを破棄しないので、他タブでの変更（相談室での目標の
  // 増減、デモデータ投入など）をホームに反映するには明示的な合図が要る。
  final ValueNotifier<int> _homeRefresh = ValueNotifier<int>(0);

  // 相談室ハブの再読込シグナル。_homeRefresh と同じ理由で要る
  // （尋問で目標の項目に答えると「本日記録済み」の表示が変わる）。
  // まとめて Map で持たないのは、どのタブが再読込を要るのかが
  // 読み取れなくなるため。
  final ValueNotifier<int> _consultRefresh = ValueNotifier<int>(0);

  // 設定の再読込シグナル。相談室で独自質問が増えるため、開くたびに読み直す。
  // saveUserSettings が .set() の全置換なので、古い設定を握ったままトグルを
  // 触ると、その間に増えた質問を巻き戻してしまう。
  final ValueNotifier<int> _settingsRefresh = ValueNotifier<int>(0);

  // 今日の記録有無。HomePage が読み込み結果を書き込み、FAB のラベルに反映する。
  final ValueNotifier<bool?> _todayDone = ValueNotifier<bool?>(null);

  // 今日聞くべき目標があるか。これも HomePage が書き込む（_todayDone と同じ流儀）。
  // FAB のためだけに Firestore をもう一度読まないため、既に目標を読んでいる
  // ホームの結果を借りる。
  final ValueNotifier<bool> _hasGoals = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    // AuthGate により認証済みでのみ表示されるため uid は非 null を前提とする
    _uid = FirebaseAuth.instance.currentUser!.uid;
  }

  @override
  void dispose() {
    _homeRefresh.dispose();
    _consultRefresh.dispose();
    _settingsRefresh.dispose();
    _todayDone.dispose();
    _hasGoals.dispose();
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
    // 相談室と設定も同じ理由で取り直す
    if (i == _consultIndex) _consultRefresh.value++;
    if (i == _settingsIndex) _settingsRefresh.value++;
  }

  // 主要動線。追跡中の事件があれば、日記の捜査より先に目標の報告を聞く。
  //
  // 日記と目標は別の記録なので画面も分けている。報告画面は pop の戻り値で
  // 「このまま捜査へ進むか」を返し、ここがその先を決める。
  //
  // pushReplacement で日記へ差し替えないのは、置き換えると元ルートの future が
  // その場で完了し、日記を書き終える前に下の refresh が走ってしまうため。
  //
  // 目標が0件のときは報告画面を開かない（空の画面が一瞬挟まるのを避ける）。
  Future<void> _openDiary() async {
    if (_hasGoals.value) {
      final toDiary = await Navigator.push<bool>(
        context,
        MaterialPageRoute<bool>(builder: (_) => GoalCheckInPage(uid: _uid)),
      );
      if (toDiary == true && mounted) {
        await Navigator.push<void>(
          context,
          MaterialPageRoute<void>(builder: (_) => const DiaryPage()),
        );
      }
    } else {
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(builder: (_) => const DiaryPage()),
      );
    }
    if (!mounted) return;
    _bumpHomeRefresh();
    // 目標の報告が入ると相談室の「本日記録済み」も変わる
    _consultRefresh.value++;
  }

  Widget _buildTab(int i) {
    switch (i) {
      case 0:
        return HomePage(
          uid: _uid,
          refreshSignal: _homeRefresh,
          todayDone: _todayDone,
          hasGoals: _hasGoals,
          onOpenConsultTab: () => _selectTab(_consultIndex),
          // 本日の事件カードからの入り口も FAB と同じ動線にする。
          // 分けたままだと「カードから入ると目標を聞かれない」という差が残る。
          onOpenDiary: _openDiary,
        );
      case 1:
        return DiaryListPage(uid: _uid);
      case 2:
        return ConsultHubPage(uid: _uid, refreshSignal: _consultRefresh);
      case 3:
        return const AnalyticsPage();
      default:
        return SettingsPage(refreshSignal: _settingsRefresh);
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
          // 相談室のアイコンに旗を使うのは、中身がチャットではなく
          // 「追跡中の事件のハブ」だから。旗はアプリ内で一貫して目標を指しており、
          // 押した先にも同じ旗が並ぶ。
          NavigationDestination(
            icon: Icon(Icons.flag_outlined),
            selectedIcon: Icon(Icons.flag),
            label: '相談室',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: '分析室',
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
