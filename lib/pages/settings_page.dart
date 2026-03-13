import 'package:flutter/material.dart';
import '../models/user_settings.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';

// ユーザーが記録したい項目を設定する画面
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

  // 設定を更新してFirestoreに即時保存する
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
      backgroundColor: const Color(0xFFF5F0EB),
      appBar: AppBar(
        title: const Text('設定'),
        backgroundColor: const Color(0xFF3D2B1F),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // 保存中はスピナーをAppBarに表示する
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _SectionHeader(title: '記録したい項目'),
                const SizedBox(height: 8),
                _SettingsCard(
                  children: [
                    _SettingsTile(
                      title: 'その日の印象的なイベント',
                      subtitle: '今日の出来事についてAIが質問します（必須）',
                      value: true,
                      onChanged: null, // 必須項目のため変更不可
                    ),
                    const Divider(height: 1),
                    _SettingsTile(
                      title: '思い出しアシスト',
                      subtitle: '午前・午後・夜に何をしたか追加で聞きます',
                      value: _settings.recallAssist,
                      onChanged: (v) =>
                          _save(_settings.copyWith(recallAssist: v)),
                    ),
                    const Divider(height: 1),
                    _SettingsTile(
                      title: '睡眠時間',
                      subtitle: '昨夜の睡眠について記録します',
                      value: _settings.recordSleep,
                      onChanged: (v) =>
                          _save(_settings.copyWith(recordSleep: v)),
                    ),
                    const Divider(height: 1),
                    _SettingsTile(
                      title: '食べたもの',
                      subtitle: '今日の食事について記録します',
                      value: _settings.recordFood,
                      onChanged: (v) =>
                          _save(_settings.copyWith(recordFood: v)),
                    ),
                    const Divider(height: 1),
                    _SettingsTile(
                      title: '運動習慣',
                      subtitle: '今日の運動について記録します',
                      value: _settings.recordExercise,
                      onChanged: (v) =>
                          _save(_settings.copyWith(recordExercise: v)),
                    ),
                    const Divider(height: 1),
                    _SettingsTile(
                      title: '勉強内容',
                      subtitle: '今日の勉強について記録します',
                      value: _settings.recordStudy,
                      onChanged: (v) =>
                          _save(_settings.copyWith(recordStudy: v)),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _SectionHeader(title: 'カスタム質問'),
                const SizedBox(height: 8),
                _SettingsCard(
                  children: [
                    // 登録済みカスタム質問を一覧表示する
                    ..._settings.customQuestions.asMap().entries.map((entry) {
                      return Column(
                        children: [
                          ListTile(
                            title: Text(entry.value),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Color(0xFF888888)),
                              onPressed: () =>
                                  _removeCustomQuestion(entry.key),
                            ),
                          ),
                          if (entry.key <
                              _settings.customQuestions.length - 1)
                            const Divider(height: 1),
                        ],
                      );
                    }),
                    if (_settings.customQuestions.isNotEmpty)
                      const Divider(height: 1),
                    // 新しいカスタム質問を入力・追加するフィールド
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _customQuestionController,
                              decoration: const InputDecoration(
                                hintText: '質問を追加（例：今日の天気は？）',
                                border: InputBorder.none,
                              ),
                              onSubmitted: (_) => _addCustomQuestion(),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle,
                                color: Color(0xFF5C3D2E)),
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

// セクションの見出しラベルウィジェット
class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.bold,
        color: Color(0xFF7A5C4A),
        letterSpacing: 0.5,
      ),
    );
  }
}

// 設定項目をまとめる白いカードウィジェット
class _SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(children: children),
      ),
    );
  }
}

// 各設定項目のスイッチ付きリストタイルウィジェット
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
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
      ),
      value: value,
      onChanged: onChanged,
      activeColor: const Color(0xFF5C3D2E),
    );
  }
}
