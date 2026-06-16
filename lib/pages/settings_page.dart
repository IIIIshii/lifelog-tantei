import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/detective_text_styles.dart';
import '../core/theme/theme_controller.dart';
import '../models/user_settings.dart';
import '../roles/roles.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/health_service.dart';
import '../services/notification_service.dart';

// ユーザーが捜査（記録）方針を設定する画面
// 記録項目のON/OFFとカスタム質問の管理を行う
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

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
  final TextEditingController _customQuestionController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _customQuestionController.dispose();
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
      await NotificationService.instance
          .schedule(newSettings.notificationHour, newSettings.notificationMinute);
    } else {
      await NotificationService.instance.cancel();
    }
  }

  // スマートウォッチ連携（Health Connect）のON/OFFを切り替える。
  // ONにする際はHealth Connect本体の有無を確認し、睡眠データの読み取り権限をリクエストする。
  Future<void> _toggleHealthSync(bool enabled) async {
    if (!enabled) {
      await _save(_settings.copyWith(healthSyncEnabled: false));
      return;
    }

    // Health Connect本体が無い端末（Android 13以前など）ではインストールを案内する
    if (!await HealthService.instance.isAvailable()) {
      if (!mounted) return;
      final install = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Health Connectが必要だ'),
          content: const Text(
              'ウォッチの睡眠記録を読み取るには「Health Connect」アプリが必要だ。インストールするか？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('インストール'),
            ),
          ],
        ),
      );
      if (install == true) {
        await HealthService.instance.installHealthConnect();
      }
      // トグルはOFFのまま。インストール完了後に改めてONにしてもらう
      return;
    }

    final granted = await HealthService.instance.requestPermissions();
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                '睡眠データの読み取りが許可されなかった。Health Connectアプリの設定からも許可できる。'),
          ),
        );
      }
      return;
    }
    await _save(_settings.copyWith(healthSyncEnabled: true));
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
    await _save(_settings.copyWith(
      notificationHour: picked.hour,
      notificationMinute: picked.minute,
    ));
    if (_settings.notificationEnabled) {
      await NotificationService.instance.schedule(picked.hour, picked.minute);
    }
  }

  // テキストフィールドの内容をカスタム質問リストに追加して保存する
  void _addCustomQuestion() {
    final text = _customQuestionController.text.trim();
    if (text.isEmpty) return;
    _customQuestionController.clear();
    _save(_settings.copyWith(
      customQuestions: [..._settings.customQuestions, text],
    ));
  }

  // 全エントリをCSV形式に変換してシェアシートを開く
  Future<void> _exportCsv() async {
    if (_uid == null) return;
    setState(() => _isExporting = true);
    try {
      final entries = await _firestore.getAllEntries(_uid!);

      // 全エントリに含まれるanswerキーを収集してCSVの列を決定する
      final allAnswerKeys = <String>{};
      for (final entry in entries) {
        final answers = entry.value['answers'] as Map<String, dynamic>?;
        if (answers != null) allAnswerKeys.addAll(answers.keys);
      }
      final answerKeys = allAnswerKeys.toList()..sort();

      // ヘッダー行
      final rows = <List<String>>[
        ['日付', '日記', ...answerKeys],
      ];

      // データ行
      for (final entry in entries) {
        final date = entry.key;
        final diary = (entry.value['diary'] as String?) ?? '';
        final answers = (entry.value['answers'] as Map<String, dynamic>?) ?? {};
        rows.add([
          date,
          diary,
          ...answerKeys.map((k) => (answers[k] as String?) ?? ''),
        ]);
      }

      // CSV文字列に変換（カンマ・改行・ダブルクォートを含む値はクォートで囲む）
      final csv = rows.map((row) => row.map(_escapeCsv).join(',')).join('\n');

      // 一時ファイルに書き込んでシェアする
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/nikkinext_export.csv');
      await file.writeAsString('\uFEFF$csv', encoding: const SystemEncoding()); // BOM付きでExcelでも文字化けしない
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv')],
        subject: 'NikkiNext 日記エクスポート',
      );
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('モックデータを書き込みました')),
        );
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

  // 指定インデックスのカスタム質問を削除して保存する
  void _removeCustomQuestion(int index) {
    final updated = List<String>.from(_settings.customQuestions)
      ..removeAt(index);
    _save(_settings.copyWith(customQuestions: updated));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // ロール一覧はレジストリ（lib/roles/）から取得する。ラベルの二重管理を避ける。
    final roles =
        kRoles.values.map((r) => (r.key, r.label)).toList(growable: false);
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
            Text('探偵事務所',
                style: DetectiveTextStyles.appBarTitle(color: c.appBarFg)),
            const SizedBox(height: 2),
            Text('― 捜査方針を設定する ―',
                style: DetectiveTextStyles.appBarSubtitle(
                    color: c.appBarSubtitle)),
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
                const _SectionHeader(
                  title: '◆ アカウント',
                  subtitle: '現在のログイン情報',
                ),
                const SizedBox(height: 8),
                _AccountCard(onLogout: _confirmLogout),
                const SizedBox(height: 28),


              // ── セクション0: 探偵キャラクター選択 ──────────────────────
              const _SectionHeader(
                title: '◆ 探偵キャラクター',
                subtitle: '尋問する探偵を選択',
              ),
              const SizedBox(height: 8),
              RadioGroup<String>(
                groupValue: _settings.selectedRole,
                onChanged: (v) {
                  if (v != null) _save(_settings.copyWith(selectedRole: v));
                },
                child: _SettingsCard(
                  children: [
                    for (var i = 0; i < roles.length; i++) ...[
                      RadioListTile<String>(
                        title: Text(roles[i].$2),
                        value: roles[i].$1,
                      ),
                      if (i < roles.length - 1)
                        Divider(height: 1, color: c.cardBorder),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 28),

                // ── セクション1: 捜査項目 ──────────────────────
                const _SectionHeader(
                  title: '◆ 捜査項目の選択',
                  subtitle: '記録したい項目を追加',
                ),
                const SizedBox(height: 8),
                _SettingsCard(
                  children: [
                    // 「その日の印象的なイベント」は必須項目のため常にON・変更不可
                    const _SettingsTile(
                      title: 'その日の印象的なイベント',
                      subtitle: '今日の出来事についてAIが質問します（必須）',
                      value: true,
                      onChanged: null,
                    ),
                    Divider(height: 1, color: c.cardBorder),
                    _SettingsTile(
                      title: '思い出しアシスト',
                      subtitle: '午前・午後・夜に何をしたか追加で聞きます',
                      value: _settings.recallAssist,
                      onChanged: (v) =>
                          _save(_settings.copyWith(recallAssist: v)),
                    ),
                    Divider(height: 1, color: c.cardBorder),
                    _SettingsTile(
                      title: '睡眠時間',
                      subtitle: '昨夜の睡眠について記録します',
                      value: _settings.recordSleep,
                      // OFFにしたらウォッチ連携も連動してOFFにする（状態の不整合を防ぐ）
                      onChanged: (v) => _save(_settings.copyWith(
                        recordSleep: v,
                        healthSyncEnabled:
                            v ? _settings.healthSyncEnabled : false,
                      )),
                    ),
                    // ウォッチ連携はHealth Connectが使えるプラットフォーム（Android）のみ表示
                    if (HealthService.instance.isSupported) ...[
                      Divider(height: 1, color: c.cardBorder),
                      _SettingsTile(
                        title: 'スマートウォッチ連携',
                        subtitle: 'Health Connectから昨夜の睡眠時間を自動取得します',
                        value: _settings.healthSyncEnabled,
                        // 睡眠時間の記録がOFFのときはグレーアウト
                        onChanged:
                            _settings.recordSleep ? _toggleHealthSync : null,
                      ),
                    ],
                    Divider(height: 1, color: c.cardBorder),
                    _SettingsTile(
                      title: '食べたもの',
                      subtitle: '今日の食事について記録します',
                      value: _settings.recordFood,
                      onChanged: (v) =>
                          _save(_settings.copyWith(recordFood: v)),
                    ),
                    Divider(height: 1, color: c.cardBorder),
                    _SettingsTile(
                      title: '運動習慣',
                      subtitle: '今日の運動について記録します',
                      value: _settings.recordExercise,
                      onChanged: (v) =>
                          _save(_settings.copyWith(recordExercise: v)),
                    ),
                    Divider(height: 1, color: c.cardBorder),
                    _SettingsTile(
                      title: '勉強内容',
                      subtitle: '今日の勉強について記録します',
                      value: _settings.recordStudy,
                      onChanged: (v) =>
                          _save(_settings.copyWith(recordStudy: v)),
                    ),
                  ],
                ),

                const SizedBox(height: 28),

                // ── セクション2: 独自質問 ──────────────────────
                const _SectionHeader(
                  title: '◆ 独自質問リスト',
                  subtitle: '自分だけの質問を追加',
                ),
                const SizedBox(height: 8),
                _SettingsCard(
                  children: [
                    // 登録済みカスタム質問を一覧表示する
                    ..._settings.customQuestions.asMap().entries.map((entry) {
                      return Column(
                        children: [
                          ListTile(
                            title: Text(
                              entry.value,
                              style: TextStyle(
                                fontSize: 14,
                                color: c.textPrimary,
                              ),
                            ),
                            // 削除ボタン
                            trailing: IconButton(
                              icon: Icon(Icons.delete_outline,
                                  color: c.textSecondary, size: 20),
                              onPressed: () =>
                                  _removeCustomQuestion(entry.key),
                            ),
                          ),
                          if (entry.key <
                              _settings.customQuestions.length - 1)
                            Divider(height: 1, color: c.cardBorder),
                        ],
                      );
                    }),

                    // 既存質問がある場合は区切り線を入れる
                    if (_settings.customQuestions.isNotEmpty)
                      Divider(height: 1, color: c.cardBorder),

                    // 新しいカスタム質問を入力・追加するフィールド
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _customQuestionController,
                              style: TextStyle(
                                fontSize: 14,
                                color: c.textPrimary,
                              ),
                              decoration: InputDecoration(
                                hintText: '質問を追加（例：今日の天気は？）',
                                hintStyle: TextStyle(
                                  color: c.textSecondary,
                                  fontSize: 13,
                                ),
                                border: InputBorder.none,
                              ),
                              onSubmitted: (_) => _addCustomQuestion(),
                            ),
                          ),
                          // 追加ボタン（ゴールドアイコン）
                          IconButton(
                            icon: Icon(Icons.add_circle, color: c.gold),
                            onPressed: _addCustomQuestion,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                // ── セクション: テーマ選択 ──────────────────────
                // ValueListenableBuilder で ThemeController を購読し、
                // 選択中テーマの変化でラジオボタンを再描画する
                const _SectionHeader(
                  title: '◆ テーマ',
                  subtitle: 'アプリの見た目を切り替える',
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<AppThemeName>(
                  valueListenable: ThemeController.instance.notifier,
                  builder: (context, currentTheme, _) {
                    return _SettingsCard(
                      children: [
                        for (var i = 0;
                            i < AppThemeName.values.length;
                            i++) ...[
                          _ThemeTile(
                            name: AppThemeName.values[i],
                            selected: currentTheme == AppThemeName.values[i],
                            onTap: () => ThemeController.instance
                                .setTheme(AppThemeName.values[i]),
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
                  const _SectionHeader(
                    title: '◆ デバッグ',
                    subtitle: 'デバッグビルドのみ表示',
                  ),
                  const SizedBox(height: 8),
                  _SettingsCard(
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
                          '直近14日分のサンプル日記を上書き保存します',
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
                            : Icon(Icons.chevron_right,
                                color: c.textSecondary),
                        onTap: _isSeeding ? null : _seedMockData,
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                ],

                // ── セクション: 通知設定 ──────────────────────
                const _SectionHeader(
                  title: '◆ 通知設定',
                  subtitle: '日記を書く時刻にリマインダーを受け取る',
                ),
                const SizedBox(height: 8),
                _SettingsCard(
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
                        style: TextStyle(
                          fontSize: 12,
                          color: c.textSecondary,
                        ),
                      ),
                      value: _settings.notificationEnabled,
                      onChanged: _toggleNotification,
                      activeThumbColor: c.gold,
                      activeTrackColor: c.goldLight,
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

                // ── セクション: エクスポート ──────────────────────
                const _SectionHeader(
                  title: '◆ データ管理',
                  subtitle: '日記データをCSVファイルでエクスポート',
                ),
                const SizedBox(height: 8),
                _SettingsCard(
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
                        '全ての日記をCSVファイルとして書き出します',
                        style: TextStyle(
                          fontSize: 12,
                          color: c.textSecondary,
                        ),
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
                          : Icon(Icons.chevron_right,
                              color: c.textSecondary),
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
// セクションの見出しウィジェット
//
// タイトル（太字・ゴールド）とその下に機能説明のサブタイトルを表示する。
// ◆ 記号でノワール感のある区切りを演出する。
// ──────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: c.gold,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 11,
            color: c.textSecondary,
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────
// 設定項目をまとめる書類風カードウィジェット
//
// ホームのCaseFileCardと同じテイストでクリーム背景＋ゴールド枠線を使用。
// 角丸を小さくして書類感を強調する。
// ──────────────────────────────────────────────────────────────
class _SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.cardBorder),
      ),
      // ClipRRectでカード内のウィジェットが角丸からはみ出ないようにする
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Column(children: children),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// 各設定項目のスイッチ付きタイルウィジェット
//
// onChangedがnullの場合はスイッチが無効（変更不可）になる。
// 必須項目（イベント記録）はnullを渡してグレーアウトする。
// ──────────────────────────────────────────────────────────────
class _SettingsTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged; // nullの場合はスイッチが無効（変更不可）

  const _SettingsTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SwitchListTile(
      title: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: c.textPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: c.textSecondary,
        ),
      ),
      value: value,
      onChanged: onChanged,
      // アクティブ時はゴールドで探偵テーマに統一（activeColorはv3.31以降非推奨）
      activeThumbColor: c.gold,
      activeTrackColor: c.goldLight,
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
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                    style: TextStyle(
                      fontSize: 12,
                      color: c.textSecondary,
                    ),
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

    return _SettingsCard(
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
