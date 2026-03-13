import 'package:flutter/material.dart';
import '../models/user_settings.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  UserSettings _settings = UserSettings.defaults();
  String? _uid;
  bool _isLoading = true;
  final TextEditingController _customController = TextEditingController();
  final AuthService _auth = AuthService();
  final FirestoreService _firestore = FirestoreService();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _uid = await _auth.signInAnonymously();
    if (_uid != null) {
      final settings = await _firestore.getUserSettings(_uid!);
      setState(() {
        _settings = settings;
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _save(UserSettings newSettings) async {
    setState(() => _settings = newSettings);
    if (_uid != null) {
      await _firestore.saveUserSettings(_uid!, newSettings);
    }
    // 通知設定を反映
    if (newSettings.notificationEnabled) {
      await NotificationService().scheduleDailyNotification(
          newSettings.notificationHour, newSettings.notificationMinute);
    } else {
      await NotificationService().cancelNotification();
    }
  }

  Future<void> _onNotificationToggled(bool enabled) async {
    if (enabled) {
      final granted = await NotificationService().requestPermission();
      if (!granted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('通知の権限が必要です。設定から許可してください。')),
        );
        return;
      }
    }
    await _save(_settings.copyWith(notificationEnabled: enabled));
  }

  Future<void> _pickNotificationTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
          hour: _settings.notificationHour,
          minute: _settings.notificationMinute),
    );
    if (picked == null) return;
    await _save(_settings.copyWith(
        notificationHour: picked.hour, notificationMinute: picked.minute));
  }

  Future<void> _addCustomQuestion() async {
    final text = _customController.text.trim();
    if (text.isEmpty) return;
    _customController.clear();
    final updated = _settings.copyWith(
      customQuestions: [..._settings.customQuestions, text],
    );
    await _save(updated);
  }

  Future<void> _removeCustomQuestion(int index) async {
    final list = List<String>.from(_settings.customQuestions)..removeAt(index);
    await _save(_settings.copyWith(customQuestions: list));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
        backgroundColor: const Color(0xFF4A4A5C),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF5F0EB),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SectionHeader(title: '記録したい内容'),
                _SettingsCard(
                  children: [
                    _SettingsTile(
                      title: 'イベントの記録',
                      subtitle: 'その日の印象的な出来事を記録する',
                      value: _settings.recordEvent,
                      onChanged: (v) =>
                          _save(_settings.copyWith(recordEvent: v)),
                    ),
                    const Divider(height: 1),
                    _SettingsTile(
                      title: '思い出しアシスト',
                      subtitle: '午前・午後・夜の行動も追加で質問する',
                      value: _settings.recallAssist,
                      onChanged: (v) =>
                          _save(_settings.copyWith(recallAssist: v)),
                    ),
                    const Divider(height: 1),
                    _SettingsTile(
                      title: '睡眠時間',
                      subtitle: '何時間寝たかを記録する',
                      value: _settings.recordSleep,
                      onChanged: (v) =>
                          _save(_settings.copyWith(recordSleep: v)),
                    ),
                    const Divider(height: 1),
                    _SettingsTile(
                      title: '食事',
                      subtitle: '食べたものを記録する',
                      value: _settings.recordFood,
                      onChanged: (v) =>
                          _save(_settings.copyWith(recordFood: v)),
                    ),
                    const Divider(height: 1),
                    _SettingsTile(
                      title: '運動',
                      subtitle: '運動習慣を記録する',
                      value: _settings.recordExercise,
                      onChanged: (v) =>
                          _save(_settings.copyWith(recordExercise: v)),
                    ),
                    const Divider(height: 1),
                    _SettingsTile(
                      title: '勉強',
                      subtitle: '勉強した内容を記録する',
                      value: _settings.recordStudy,
                      onChanged: (v) =>
                          _save(_settings.copyWith(recordStudy: v)),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _SectionHeader(title: 'カスタム質問'),
                _SettingsCard(
                  children: [
                    ..._settings.customQuestions.asMap().entries.map((e) {
                      return Column(
                        children: [
                          if (e.key > 0) const Divider(height: 1),
                          ListTile(
                            title: Text(e.value),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.redAccent),
                              onPressed: () => _removeCustomQuestion(e.key),
                            ),
                          ),
                        ],
                      );
                    }),
                    if (_settings.customQuestions.isNotEmpty)
                      const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _customController,
                              decoration: const InputDecoration(
                                hintText: '質問を入力...',
                                border: InputBorder.none,
                              ),
                              onSubmitted: (_) => _addCustomQuestion(),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline,
                                color: Color(0xFF4A4A5C)),
                            onPressed: _addCustomQuestion,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _SectionHeader(title: '通知'),
                _SettingsCard(
                  children: [
                    _SettingsTile(
                      title: '日記リマインダー',
                      subtitle: '毎日指定した時刻に通知を受け取る',
                      value: _settings.notificationEnabled,
                      onChanged: _onNotificationToggled,
                    ),
                    if (_settings.notificationEnabled) ...[
                      const Divider(height: 1),
                      ListTile(
                        title: const Text('通知時刻',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500)),
                        trailing: Text(
                          '${_settings.notificationHour.toString().padLeft(2, '0')}:${_settings.notificationMinute.toString().padLeft(2, '0')}',
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF4A4A5C)),
                        ),
                        onTap: _pickNotificationTime,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Color(0xFF7A5C4A),
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

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

class _SettingsTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle,
          style: const TextStyle(fontSize: 12, color: Color(0xFF888888))),
      value: value,
      activeThumbColor: const Color(0xFF4A4A5C),
      onChanged: onChanged,
    );
  }
}
