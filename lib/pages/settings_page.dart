import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/daily_record.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/detective_text_styles.dart';
import '../core/theme/theme_controller.dart';
import '../models/user_settings.dart';
import '../roles/roles.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../widgets/settings_section.dart';
import 'ai_data_notice_page.dart';
import 'field_settings_page.dart';
import 'role_select_page.dart';

// 設定画面。担当探偵・記録する項目・テーマ・通知・データ管理をまとめる。
// 記録する項目の中身は FieldSettingsPage（push）で編集する。
class SettingsPage extends StatefulWidget {
  /// MainShell が値を進めるたびに設定を読み直すシグナル。
  /// タブは IndexedStack で保持され破棄されないため、探偵の指名をホームから
  /// 変えてもこの合図が無いと画面に現れない。さらに saveUserSettings は
  /// .set() の全置換なので、古い設定を握ったまま通知を触ると指名を巻き戻してしまう。
  final ValueListenable<int> refreshSignal;

  const SettingsPage({super.key, required this.refreshSignal});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  UserSettings _settings = UserSettings.defaults();
  String? _uid;
  bool _isLoading = true;
  bool _isSaving = false; // 保存中フラグ（AppBarにスピナーを表示するために使用）
  bool _isExporting = false;
  bool _isSeeding = false;

  final FirestoreService _firestore = FirestoreService();

  @override
  void initState() {
    super.initState();
    widget.refreshSignal.addListener(_loadSettings);
    _loadSettings();
  }

  @override
  void dispose() {
    widget.refreshSignal.removeListener(_loadSettings);
    super.dispose();
  }

  // FirestoreからUserSettingsを読み込む
  Future<void> _loadSettings() async {
    _uid = FirebaseAuth.instance.currentUser!.uid;
    final settings = await _firestore.getUserSettings(_uid!);
    setState(() {
      _settings = settings;
      _isLoading = false;
    });
  }

  // ログアウト確認ダイアログ。ゲストの場合はデータ喪失を強めに警告する。
  // 成功時の遷移は AuthGate が自動で行うため、ここでは Navigator を触らない。
  Future<void> _confirmLogout() async {
    final user = FirebaseAuth.instance.currentUser;
    final isGuest = user?.isAnonymous ?? false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('捜査を中断するか？'),
        content: Text(
          isGuest
              ? 'ゲストモードでログアウトすると、この端末の記録は再アクセスできなくなる。本当にいいか？'
              : 'ログアウトすると次回はもう一度ログインが必要だ。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ログアウト'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await AuthService.instance.signOut();
    }
  }

  // 設定を更新してFirestoreに即時保存する（トグル操作のたびに呼ばれる）
  Future<void> _save(UserSettings newSettings) async {
    setState(() {
      _settings = newSettings;
      _isSaving = true;
    });
    await _firestore.saveUserSettings(_uid!, newSettings);
    setState(() => _isSaving = false);
  }

  // 通知ON/OFFを切り替えてスケジュールを更新する
  Future<void> _toggleNotification(bool enabled) async {
    final newSettings = _settings.copyWith(notificationEnabled: enabled);
    await _save(newSettings);
    if (enabled) {
      await NotificationService.instance.schedule(
        newSettings.notificationHour,
        newSettings.notificationMinute,
      );
    } else {
      await NotificationService.instance.cancel();
    }
  }

  // 時刻ピッカーを表示して通知時刻を更新する
  Future<void> _pickNotificationTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: _settings.notificationHour,
        minute: _settings.notificationMinute,
      ),
    );
    if (picked == null) return;
    await _save(
      _settings.copyWith(
        notificationHour: picked.hour,
        notificationMinute: picked.minute,
      ),
    );
    if (_settings.notificationEnabled) {
      await NotificationService.instance.schedule(picked.hour, picked.minute);
    }
  }

  // 記録する項目の設定を開く
  void _openFieldSettings() {
    if (_uid == null) return;
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => FieldSettingsPage(uid: _uid!)),
    );
  }

  // 日々の記録と日記をCSV形式に変換してシェアシートを開く。
  // 1行が1日で、列は「日付・日記・記録の各項目」。
  Future<void> _exportCsv() async {
    if (_uid == null) return;
    setState(() => _isExporting = true);
    try {
      final recordsFuture = _firestore.getAllRecords(_uid!);
      final diariesFuture = _firestore.getAllDiaries(_uid!);
      final fieldsFuture = _firestore.getFields(_uid!);
      final goalsFuture = _firestore.getAllGoals(_uid!);
      final records = await recordsFuture;
      final diaries = await diariesFuture;
      final fields = await fieldsFuture;
      final goals = await goalsFuture;

      // 使わなくなった項目・閉じた目標の項目も、過去の値があれば列にする
      final index = fieldIndex(fields, [...goals.active, ...goals.closed]);
      final days = mergeDays(records, diaries).reversed.toList(); // 新しい順
      final columns = [
        for (final field in index.values)
          if (days.any((d) => valueOf(d.value, field.id) != null)) field,
      ];

      final rows = <List<String>>[
        ['日付', '日記', for (final field in columns) field.promptLabel],
        for (final day in days)
          [
            day.key,
            (day.value['diary'] as String?) ?? '',
            for (final field in columns)
              formatValue(field, valueOf(day.value, field.id)) ?? '',
          ],
      ];

      // CSV文字列に変換（カンマ・改行・ダブルクォートを含む値はクォートで囲む）
      final csv = rows.map((row) => row.map(_escapeCsv).join(',')).join('\n');

      // 一時ファイルに書き込んでシェアする
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/nikkinext_export.csv');
      await file.writeAsString(
        '\uFEFF$csv',
        encoding: const SystemEncoding(),
      ); // BOM付きでExcelでも文字化けしない
      await Share.shareXFiles([
        XFile(file.path, mimeType: 'text/csv'),
      ], subject: 'NikkiNext 日記エクスポート');
    } finally {
      setState(() => _isExporting = false);
    }
  }

  // モックデータを書き込む（デバッグビルドのみ表示）
  Future<void> _seedMockData() async {
    if (_uid == null) return;
    setState(() => _isSeeding = true);
    try {
      await _firestore.seedMockData(_uid!);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('モックデータを書き込みました')));
      }
    } finally {
      setState(() => _isSeeding = false);
    }
  }

  String _escapeCsv(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,

      // ── AppBar ──────────────────────────────────────────────
      // ホーム画面と同じくサブタイトル付きで探偵事務所の雰囲気を演出
      appBar: AppBar(
        backgroundColor: c.appBarBg,
        foregroundColor: c.appBarFg,
        elevation: 0,
        toolbarHeight: 64,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '探偵事務所',
              style: DetectiveTextStyles.appBarTitle(color: c.appBarFg),
            ),
            const SizedBox(height: 2),
            Text(
              '― 捜査方針を設定する ―',
              style: DetectiveTextStyles.appBarSubtitle(
                color: c.appBarSubtitle,
              ),
            ),
          ],
        ),
        actions: [
          // 保存中はAppBar右端にゴールドのスピナーを表示する
          if (_isSaving)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: c.goldLight,
                  strokeWidth: 2,
                ),
              ),
            ),
        ],
      ),

      // ── Body ────────────────────────────────────────────────
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: c.gold))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // ── セクション: アカウント ──────────────────────
                const SectionHeader(title: '◆ アカウント', subtitle: '現在のログイン情報'),
                const SizedBox(height: 8),
                _AccountCard(onLogout: _confirmLogout),
                const SizedBox(height: 28),

                // ── セクション: 担当探偵 ──────────────────────
                // もとはボトムナビの1タブ。5つの枠を相談室へ譲り、
                // 設定配下の push に戻した。設定の底ではなく先頭に近い位置へ
                // 置くのは、直前までトップレベルにあったものを埋もれさせないため。
                const SectionHeader(title: '◆ 担当探偵', subtitle: '尋問する探偵を指名する'),
                const SizedBox(height: 8),
                SettingsCard(
                  children: [
                    ListTile(
                      leading: Icon(Icons.person_search, color: c.gold),
                      title: Text(
                        '探偵キャラクター',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: c.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        roleFor(_settings.selectedRole).label,
                        style: TextStyle(fontSize: 12, color: c.textSecondary),
                      ),
                      trailing: Icon(
                        Icons.chevron_right,
                        color: c.textSecondary,
                      ),
                      // 戻ったら読み直す。RoleSelectPage は同じ
                      // settings/preferences を直接書くので、ここが握っている
                      // _settings は選び直したあと古くなる。
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const RoleSelectPage(),
                        ),
                      ).then((_) => _loadSettings()),
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                // ── セクション: 記録する項目 ──────────────────
                // 日々の記録の表に並べる項目（睡眠時間・気分・自分で足した項目など）。
                // 項目が増えると1画面に収まらないので、中身は別ページで編集する。
                const SectionHeader(title: '◆ 記録する項目', subtitle: '日々の記録の表に並べるもの'),
                const SizedBox(height: 8),
                SettingsCard(
                  children: [
                    ListTile(
                      leading: Icon(Icons.fact_check_outlined, color: c.gold),
                      title: Text(
                        '記録する項目を編集',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: c.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        '項目の追加・並べ替え・曜日・日記に使うか',
                        style: TextStyle(fontSize: 12, color: c.textSecondary),
                      ),
                      trailing: Icon(
                        Icons.chevron_right,
                        color: c.textSecondary,
                      ),
                      onTap: _openFieldSettings,
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                // ── セクション: テーマ選択 ──────────────────────
                // ValueListenableBuilder で ThemeController を購読し、
                // 選択中テーマの変化でラジオボタンを再描画する
                const SectionHeader(title: '◆ テーマ', subtitle: 'アプリの見た目を切り替える'),
                const SizedBox(height: 8),
                ValueListenableBuilder<AppThemeName>(
                  valueListenable: ThemeController.instance.notifier,
                  builder: (context, currentTheme, _) {
                    return SettingsCard(
                      children: [
                        for (
                          var i = 0;
                          i < AppThemeName.values.length;
                          i++
                        ) ...[
                          _ThemeTile(
                            name: AppThemeName.values[i],
                            selected: currentTheme == AppThemeName.values[i],
                            onTap: () => ThemeController.instance.setTheme(
                              AppThemeName.values[i],
                            ),
                          ),
                          if (i < AppThemeName.values.length - 1)
                            Divider(height: 1, color: c.cardBorder),
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 28),

                // ── セクション3: データ管理 ──────────────────────
                // デバッグビルドのみシードボタンを表示する
                if (kDebugMode) ...[
                  const SectionHeader(title: '◆ デバッグ', subtitle: 'デバッグビルドのみ表示'),
                  const SizedBox(height: 8),
                  SettingsCard(
                    children: [
                      ListTile(
                        leading: Icon(Icons.bug_report_outlined, color: c.gold),
                        title: Text(
                          'モックデータを書き込む',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: c.textPrimary,
                          ),
                        ),
                        subtitle: Text(
                          '直近14日分のサンプルの記録と日記を上書き保存します',
                          style: TextStyle(
                            fontSize: 12,
                            color: c.textSecondary,
                          ),
                        ),
                        trailing: _isSeeding
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: c.gold,
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(Icons.chevron_right, color: c.textSecondary),
                        onTap: _isSeeding ? null : _seedMockData,
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                ],

                // ── セクション: 通知設定 ──────────────────────
                const SectionHeader(
                  title: '◆ 通知設定',
                  subtitle: '日記を書く時刻にリマインダーを受け取る',
                ),
                const SizedBox(height: 8),
                SettingsCard(
                  children: [
                    SwitchListTile(
                      title: Text(
                        '毎日リマインダー',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: c.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        '設定した時刻に通知で日記を促します',
                        style: TextStyle(fontSize: 12, color: c.textSecondary),
                      ),
                      value: _settings.notificationEnabled,
                      onChanged: _toggleNotification,
                      activeThumbColor: c.onAccent,
                      activeTrackColor: c.gold,
                    ),
                    Divider(height: 1, color: c.cardBorder),
                    ListTile(
                      leading: Icon(
                        Icons.access_time,
                        color: _settings.notificationEnabled
                            ? c.gold
                            : c.textSecondary,
                      ),
                      title: Text(
                        '通知時刻',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: _settings.notificationEnabled
                              ? c.textPrimary
                              : c.textSecondary,
                        ),
                      ),
                      subtitle: Text(
                        '${_settings.notificationHour.toString().padLeft(2, '0')}:${_settings.notificationMinute.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontSize: 12,
                          color: _settings.notificationEnabled
                              ? c.gold
                              : c.textSecondary,
                        ),
                      ),
                      trailing: Icon(
                        Icons.chevron_right,
                        color: _settings.notificationEnabled
                            ? c.textSecondary
                            : c.cardBorder,
                      ),
                      onTap: _settings.notificationEnabled
                          ? _pickNotificationTime
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                // ── セクション: AIへの送信 ──────────────────────
                // 日記と記録は個人的な内容なので、AI に渡ることと、その範囲を
                // 設定からいつでも読めるようにする。一覧は別ページに置く。
                const SectionHeader(
                  title: '◆ AIへの送信について',
                  subtitle: '入力した内容が、AIに渡る範囲',
                ),
                const SizedBox(height: 8),
                SettingsCard(
                  children: [
                    ListTile(
                      leading: Icon(Icons.shield_outlined, color: c.gold),
                      title: Text(
                        '何がAIに送られるか',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: c.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        '記録・会話・日記が、質問や日記づくりのために送られます',
                        style: TextStyle(fontSize: 12, color: c.textSecondary),
                      ),
                      trailing: Icon(
                        Icons.chevron_right,
                        color: c.textSecondary,
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const AiDataNoticePage(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                // ── セクション: エクスポート ──────────────────────
                const SectionHeader(
                  title: '◆ データ管理',
                  subtitle: '記録と日記をCSVファイルでエクスポート',
                ),
                const SizedBox(height: 8),
                SettingsCard(
                  children: [
                    ListTile(
                      leading: Icon(Icons.download_outlined, color: c.gold),
                      title: Text(
                        'CSVでエクスポート',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: c.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        '全ての日々の記録と日記をCSVファイルとして書き出します',
                        style: TextStyle(fontSize: 12, color: c.textSecondary),
                      ),
                      trailing: _isExporting
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: c.gold,
                                strokeWidth: 2,
                              ),
                            )
                          : Icon(Icons.chevron_right, color: c.textSecondary),
                      onTap: _isExporting ? null : _exportCsv,
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// テーマ選択用の1行タイル
//
// 左にテーマのカラーパレットプレビュー（3色ドット）、
// 中央にテーマ名と説明、右に選択状態のラジオ風マークを表示する。
// タップで onTap を発火させて ThemeController.setTheme() を呼ぶ。
// ──────────────────────────────────────────────────────────────
class _ThemeTile extends StatelessWidget {
  final AppThemeName name;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeTile({
    required this.name,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // そのテーマ自体の色を引いてプレビューに使う（ライブプレビュー）
    final preview = colorsOf(name);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // ── カラーパレットプレビュー（3色ドット） ──
            _ColorDot(color: preview.background, border: preview.cardBorder),
            const SizedBox(width: 4),
            _ColorDot(color: preview.appBarBg, border: preview.cardBorder),
            const SizedBox(width: 4),
            _ColorDot(color: preview.gold, border: preview.cardBorder),
            const SizedBox(width: 16),

            // ── テーマ名と説明 ──
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    name.description,
                    style: TextStyle(fontSize: 12, color: c.textSecondary),
                  ),
                ],
              ),
            ),

            // ── 選択状態マーク（チェック or 空円） ──
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? c.gold : c.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

// テーマプレビュー用の小さな色ドット
class _ColorDot extends StatelessWidget {
  final Color color;
  final Color border;
  const _ColorDot({required this.color, required this.border});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: border, width: 1),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// アカウントセクションのカード
//
// 現在ログイン中のユーザー（Google か 匿名）を表示し、ログアウト導線を提供する。
// 匿名ユーザーには「端末固有のデータ」である旨を警告として併記する。
// ──────────────────────────────────────────────────────────────
class _AccountCard extends StatelessWidget {
  final VoidCallback onLogout;

  const _AccountCard({required this.onLogout});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final user = FirebaseAuth.instance.currentUser;
    final isGuest = user?.isAnonymous ?? true;
    final displayName = isGuest
        ? 'ゲスト'
        : (user?.displayName?.isNotEmpty == true
              ? user!.displayName!
              : '名前未設定');
    final subtitle = isGuest
        ? '※ 端末固有のデータです。他端末からは参照できません'
        : (user?.email ?? '');

    return SettingsCard(
      children: [
        ListTile(
          leading: Icon(
            isGuest ? Icons.person_outline : Icons.account_circle,
            color: c.gold,
          ),
          title: Text(
            displayName,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: c.textPrimary,
            ),
          ),
          subtitle: subtitle.isEmpty
              ? null
              : Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: c.textSecondary),
                ),
        ),
        Divider(height: 1, color: c.cardBorder),
        ListTile(
          leading: Icon(Icons.logout, color: c.textSecondary),
          title: Text(
            'ログアウト',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: c.textPrimary,
            ),
          ),
          trailing: Icon(Icons.chevron_right, color: c.textSecondary),
          onTap: onLogout,
        ),
      ],
    );
  }
}
