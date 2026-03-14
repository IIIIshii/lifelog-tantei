import 'package:flutter/material.dart';
import '../core/theme/detective_theme.dart';
import '../models/user_settings.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';

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

  final AuthService _auth = AuthService();
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
    _uid = await _auth.signInAnonymously();
    final settings = await _firestore.getUserSettings(_uid!);
    setState(() {
      _settings = settings;
      _isLoading = false;
    });
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

  // テキストフィールドの内容をカスタム質問リストに追加して保存する
  void _addCustomQuestion() {
    final text = _customQuestionController.text.trim();
    if (text.isEmpty) return;
    _customQuestionController.clear();
    _save(_settings.copyWith(
      customQuestions: [..._settings.customQuestions, text],
    ));
  }

  // 指定インデックスのカスタム質問を削除して保存する
  void _removeCustomQuestion(int index) {
    final updated = List<String>.from(_settings.customQuestions)
      ..removeAt(index);
    _save(_settings.copyWith(customQuestions: updated));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DetectiveTheme.background,

      // ── AppBar ──────────────────────────────────────────────
      // ホーム画面と同じくサブタイトル付きで探偵事務所の雰囲気を演出
      appBar: AppBar(
        backgroundColor: DetectiveTheme.appBarBg,
        foregroundColor: const Color(0xFFE8DCC8),
        elevation: 0,
        toolbarHeight: 64,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('探偵事務所', style: DetectiveTheme.appBarTitle),
            const SizedBox(height: 2),
            const Text('― 捜査方針を設定する ―',
                style: DetectiveTheme.appBarSubtitle),
          ],
        ),
        actions: [
          // 保存中はAppBar右端にゴールドのスピナーを表示する
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: DetectiveTheme.goldLight,
                  strokeWidth: 2,
                ),
              ),
            ),
        ],
      ),

      // ── Body ────────────────────────────────────────────────
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: DetectiveTheme.gold),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
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
                    const Divider(height: 1, color: DetectiveTheme.cardBorder),
                    _SettingsTile(
                      title: '思い出しアシスト',
                      subtitle: '午前・午後・夜に何をしたか追加で聞きます',
                      value: _settings.recallAssist,
                      onChanged: (v) =>
                          _save(_settings.copyWith(recallAssist: v)),
                    ),
                    const Divider(height: 1, color: DetectiveTheme.cardBorder),
                    _SettingsTile(
                      title: '睡眠時間',
                      subtitle: '昨夜の睡眠について記録します',
                      value: _settings.recordSleep,
                      onChanged: (v) =>
                          _save(_settings.copyWith(recordSleep: v)),
                    ),
                    const Divider(height: 1, color: DetectiveTheme.cardBorder),
                    _SettingsTile(
                      title: '食べたもの',
                      subtitle: '今日の食事について記録します',
                      value: _settings.recordFood,
                      onChanged: (v) =>
                          _save(_settings.copyWith(recordFood: v)),
                    ),
                    const Divider(height: 1, color: DetectiveTheme.cardBorder),
                    _SettingsTile(
                      title: '運動習慣',
                      subtitle: '今日の運動について記録します',
                      value: _settings.recordExercise,
                      onChanged: (v) =>
                          _save(_settings.copyWith(recordExercise: v)),
                    ),
                    const Divider(height: 1, color: DetectiveTheme.cardBorder),
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
                              style: const TextStyle(
                                fontSize: 14,
                                color: DetectiveTheme.textPrimary,
                              ),
                            ),
                            // 削除ボタン
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: DetectiveTheme.textSecondary,
                                  size: 20),
                              onPressed: () =>
                                  _removeCustomQuestion(entry.key),
                            ),
                          ),
                          if (entry.key <
                              _settings.customQuestions.length - 1)
                            const Divider(
                                height: 1,
                                color: DetectiveTheme.cardBorder),
                        ],
                      );
                    }),

                    // 既存質問がある場合は区切り線を入れる
                    if (_settings.customQuestions.isNotEmpty)
                      const Divider(
                          height: 1, color: DetectiveTheme.cardBorder),

                    // 新しいカスタム質問を入力・追加するフィールド
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _customQuestionController,
                              style: const TextStyle(
                                fontSize: 14,
                                color: DetectiveTheme.textPrimary,
                              ),
                              decoration: const InputDecoration(
                                hintText: '質問を追加（例：今日の天気は？）',
                                hintStyle: TextStyle(
                                  color: DetectiveTheme.textSecondary,
                                  fontSize: 13,
                                ),
                                border: InputBorder.none,
                              ),
                              onSubmitted: (_) => _addCustomQuestion(),
                            ),
                          ),
                          // 追加ボタン（ゴールドアイコン）
                          IconButton(
                            icon: const Icon(Icons.add_circle,
                                color: DetectiveTheme.gold),
                            onPressed: _addCustomQuestion,
                          ),
                        ],
                      ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: DetectiveTheme.gold,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 11,
            color: DetectiveTheme.textSecondary,
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
    return Container(
      decoration: BoxDecoration(
        color: DetectiveTheme.cardBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: DetectiveTheme.cardBorder),
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
    return SwitchListTile(
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: DetectiveTheme.textPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          fontSize: 12,
          color: DetectiveTheme.textSecondary,
        ),
      ),
      value: value,
      onChanged: onChanged,
      // アクティブ時はゴールドで探偵テーマに統一（activeColorはv3.31以降非推奨）
      activeThumbColor: DetectiveTheme.gold,
      activeTrackColor: DetectiveTheme.goldLight,
    );
  }
}
