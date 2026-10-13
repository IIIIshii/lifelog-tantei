import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'case_files_page.dart';
import 'consult_hub_page.dart';
import 'diary_page.dart';
import 'home_page.dart';
import 'record_sheet_page.dart';
import 'settings_page.dart';

// ──────────────────────────────────────────────────────────────
// アプリのシェル。ボトムナビゲーションで4つのタブを束ねる。
//
//   事務所（今日）／ 事件簿（記録確認）／ 相談室（目標）／ 設定
//
// ナビゲーションバーには「行き先」だけを置く（Material 3 の指針）。
// 毎日の主要動線である「今日の捜査」は行き先ではなく操作なので、タブにせず
// 事務所タブの Extended FAB に置いている。押すと、終わっていない段だけを
// 日々の記録 → 聴取（日記）の順に開く。各段だけを開く入口は事務所のカードにある。
//
// 以前は事件簿と分析室が別々のタブだった。どちらも「記録を読み返す」行き先なので
// 事件簿タブの中の上部タブにまとめ、5つから4つに減らした。
// ──────────────────────────────────────────────────────────────
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  static const int _homeIndex = 0;
  static const int _caseFilesIndex = 1;
  static const int _consultIndex = 2;
  static const int _settingsIndex = 3;
  static const int _tabCount = 4;

  late final String _uid;

  int _index = _homeIndex;

  // 一度でも開いたタブの index。
  // 事件簿（分析）・相談室・設定は initState で Firestore を読むため、
  // 素の IndexedStack だと起動時に全画面ぶん一斉にフェッチしてしまう。
  // 未訪問のタブには空ウィジェットを置き、初回表示まで生成を遅らせる。
  final Set<int> _visited = {_homeIndex};

  // 各タブの再読込シグナル。
  // IndexedStack はページを破棄しないので、他タブでの変更（相談室での目標の
  // 増減、記録の書き足し、デモデータ投入など）を反映するには明示的な合図が要る。
  // まとめて Map で持たないのは、どのタブが再読込を要るのかが読み取れなくなるため。
  final ValueNotifier<int> _homeRefresh = ValueNotifier<int>(0);
  final ValueNotifier<int> _caseFilesRefresh = ValueNotifier<int>(0);
  final ValueNotifier<int> _consultRefresh = ValueNotifier<int>(0);
  final ValueNotifier<int> _settingsRefresh = ValueNotifier<int>(0);

  // 今日の進み具合。HomePage が読み込み結果を書き込み、FAB のラベルと
  // 「日々の記録を挟むか」の判定に使う（FAB のために Firestore を読み直さない）。
  final ValueNotifier<TodayStatus?> _todayStatus = ValueNotifier<TodayStatus?>(
    null,
  );

  @override
  void initState() {
    super.initState();
    // AuthGate により認証済みでのみ表示されるため uid は非 null を前提とする
    _uid = FirebaseAuth.instance.currentUser!.uid;
  }

  @override
  void dispose() {
    _homeRefresh.dispose();
    _caseFilesRefresh.dispose();
    _consultRefresh.dispose();
    _settingsRefresh.dispose();
    _todayStatus.dispose();
    super.dispose();
  }

  void _selectTab(int i) {
    setState(() {
      _index = i;
      _visited.add(i);
    });
    // タブに戻ってきたタイミングで最新の状態を取り直す
    switch (i) {
      case _homeIndex:
        _homeRefresh.value++;
      case _caseFilesIndex:
        _caseFilesRefresh.value++;
      case _consultIndex:
        _consultRefresh.value++;
      case _settingsIndex:
        _settingsRefresh.value++;
    }
  }

  // 主要動線。今日の記録がまだ埋まっていなければ表を先に開き、
  // 「日記へ進む」で戻ってきたら聴取へ続ける。記録が埋まっていれば聴取から始める。
  //
  // 表と聴取を別画面にしているのは、記録は1日に何度でも書き足すもので、
  // 聴取は日記を書くときに1回通すものだから。表は pop の戻り値で
  // 「このまま日記へ進むか」を返し、ここがその先を決める。
  //
  // pushReplacement で聴取へ差し替えないのは、置き換えると元ルートの future が
  // その場で完了し、日記を書き終える前に下の再読込が走ってしまうため。
  Future<void> _startToday() async {
    final status = _todayStatus.value;
    final needsRecord =
        status == null || (status.total > 0 && status.filled < status.total);
    if (needsRecord) {
      final toDiary = await Navigator.push<bool>(
        context,
        MaterialPageRoute<bool>(
          builder: (_) => RecordSheetPage(uid: _uid, continueToDiary: true),
        ),
      );
      if (toDiary != true || !mounted) {
        _refreshAfterCase();
        return;
      }
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(builder: (_) => const DiaryPage()),
    );
    if (!mounted) return;
    _refreshAfterCase();
  }

  // 記録・日記を書いたあとに変わる画面を取り直す
  void _refreshAfterCase() {
    _homeRefresh.value++;
    // 目標の項目を記録すると相談室の「本日記録済み」も変わる
    _consultRefresh.value++;
    _caseFilesRefresh.value++;
  }

  Widget _buildTab(int i) {
    switch (i) {
      case _homeIndex:
        return HomePage(
          uid: _uid,
          refreshSignal: _homeRefresh,
          todayStatus: _todayStatus,
          onOpenConsultTab: () => _selectTab(_consultIndex),
        );
      case _caseFilesIndex:
        return CaseFilesPage(uid: _uid, refreshSignal: _caseFilesRefresh);
      case _consultIndex:
        return ConsultHubPage(uid: _uid, refreshSignal: _consultRefresh);
      default:
        return SettingsPage(refreshSignal: _settingsRefresh);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 各タブページは自前の Scaffold と AppBar を持つ。シェルがルート
      // （AuthGate の直下）なので Navigator.canPop が false になり、
      // AppBar の戻る矢印は自動的に出ない。
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
          ? ValueListenableBuilder<TodayStatus?>(
              valueListenable: _todayStatus,
              builder: (context, status, _) {
                final started =
                    status != null && (status.filled > 0 || status.diaryDone);
                return FloatingActionButton.extended(
                  onPressed: _startToday,
                  icon: const Icon(Icons.edit_note),
                  label: Text(started ? '捜査を続ける' : '今日の捜査を始める'),
                );
              },
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
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '設定',
          ),
        ],
      ),
    );
  }
}
