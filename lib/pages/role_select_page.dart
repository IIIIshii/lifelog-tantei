import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/detective_text_styles.dart';
import '../models/user_settings.dart';
import '../roles/roles.dart';
import '../services/firestore_service.dart';

// 探偵キャラクター（ロール）を選ぶ専用画面。
// ホーム画面から遷移し、選んだキャラを UserSettings.selectedRole として即時保存する。
// 保存先は SettingsPage と同じ Firestore users/{uid}/settings/preferences。
class RoleSelectPage extends StatefulWidget {
  const RoleSelectPage({super.key});

  @override
  State<RoleSelectPage> createState() => _RoleSelectPageState();
}

class _RoleSelectPageState extends State<RoleSelectPage> {
  UserSettings _settings = UserSettings.defaults();
  String? _uid;
  bool _isLoading = true;
  bool _isSaving = false; // 保存中フラグ（AppBarにスピナーを表示するために使用）

  final FirestoreService _firestore = FirestoreService();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  // Firestoreから現在の設定を読み込み、選択中ロールを反映する
  Future<void> _loadSettings() async {
    _uid = FirebaseAuth.instance.currentUser!.uid;
    final settings = await _firestore.getUserSettings(_uid!);
    setState(() {
      _settings = settings;
      _isLoading = false;
    });
  }

  // 選択ロールを更新してFirestoreに即時保存する
  Future<void> _selectRole(String roleKey) async {
    if (roleKey == _settings.selectedRole) return;
    final newSettings = _settings.copyWith(selectedRole: roleKey);
    setState(() {
      _settings = newSettings;
      _isSaving = true;
    });
    await _firestore.saveUserSettings(_uid!, newSettings);
    setState(() => _isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // ロール一覧はレジストリ（lib/roles/）から取得する
    final roles = kRoles.values.toList(growable: false);
    return Scaffold(
      backgroundColor: c.background,

      // ── AppBar ──────────────────────────────────────────────
      // ホーム・設定画面と同じくサブタイトル付きで探偵事務所の雰囲気を演出
      appBar: AppBar(
        backgroundColor: c.appBarBg,
        foregroundColor: c.appBarFg,
        elevation: 0,
        toolbarHeight: 64,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('探偵キャラクター',
                style: DetectiveTextStyles.appBarTitle(color: c.appBarFg)),
            const SizedBox(height: 2),
            Text('― 尋問する探偵を指名する ―',
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
          : ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: roles.length,
              separatorBuilder: (context, index) => const SizedBox(height: 16),
              itemBuilder: (context, i) {
                final role = roles[i];
                return _RoleCard(
                  role: role,
                  selected: role.key == _settings.selectedRole,
                  onTap: () => _selectRole(role.key),
                );
              },
            ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// 探偵キャラ1体分の選択カード
//
// 名前（太字）＋一言説明を表示し、左端のゴールドアクセントと選択状態マークで
// ホームのCaseFileCardと統一感のある書類風デザインにする。
// 選択中はカード枠をゴールドにして強調する。
// ──────────────────────────────────────────────────────────────
class _RoleCard extends StatelessWidget {
  final Role role;
  final bool selected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.role,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(
          color: selected ? c.gold : c.cardBorder,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 左端のゴールドアクセントボーダー
              Container(
                width: 4,
                color: c.gold,
              ),

              // カード本文
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 16),
                  child: Row(
                    children: [
                      Icon(Icons.person_search, color: c.gold, size: 28),
                      const SizedBox(width: 16),

                      // 名前 + 一言説明
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(role.label,
                                style: DetectiveTextStyles.cardTitle(
                                    color: c.textPrimary)),
                            const SizedBox(height: 4),
                            Text(role.description,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: c.textSecondary,
                                  height: 1.4,
                                )),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),

                      // 選択状態マーク
                      Icon(
                        selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: selected ? c.gold : c.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
