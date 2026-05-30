import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/detective_text_styles.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';

// アプリ起動時の認証画面。Googleログインまたはゲスト（匿名）利用を選ばせる。
// 認証成功後の遷移は AuthGate が StreamBuilder で自動的に行うため、
// このページ自身は Navigator.push を呼ばない。
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _isLoading = false;

  Future<void> _signInWithGoogle() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      await AuthService.instance.signInWithGoogle();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        // ユーザーが意図的にキャンセルした場合はエラー表示しない
        return;
      }
      if (mounted) {
        _showError('Googleログインに失敗しました', e.description ?? e.code.name);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) _showError('認証に失敗しました', e.message ?? e.code);
    } catch (e) {
      if (mounted) _showError('予期せぬエラーが発生しました', '$e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInAsGuest() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      await AuthService.instance.signInAsGuest();
    } on FirebaseAuthException catch (e) {
      if (mounted) _showError('ゲストログインに失敗しました', e.message ?? e.code);
    } catch (e) {
      if (mounted) _showError('予期せぬエラーが発生しました', '$e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // デモ用：ゲストログイン後、モックの事件簿14日分を一括投入する。
  // 投入後の画面遷移は AuthGate が自動で行う（一覧はリアルタイム購読のため
  // seed 完了次第ライブで反映される）。
  Future<void> _startDemo() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      await AuthService.instance.signInAsGuest();
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await FirestoreService().seedMockData(uid);
    } on FirebaseAuthException catch (e) {
      if (mounted) _showError('デモの開始に失敗しました', e.message ?? e.code);
    } catch (e) {
      if (mounted) _showError('予期せぬエラーが発生しました', '$e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String title, String message) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: SelectableText(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── ヘッダー ────────────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 32),
                  decoration: BoxDecoration(
                    color: c.cardBg,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: c.cardBorder),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.travel_explore, color: c.gold, size: 56),
                      const SizedBox(height: 16),
                      Text(
                        'ライフログ探偵',
                        style: DetectiveTextStyles.appBarTitle(color: c.textPrimary)
                            .copyWith(fontSize: 24),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '― 事件、受け付けます ―',
                        style: DetectiveTextStyles.appBarSubtitle(
                            color: c.textSecondary),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        '事件簿を開くには認証が必要です',
                        style: TextStyle(
                            fontSize: 13, color: c.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // ── Googleログインボタン ────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _signInWithGoogle,
                    icon: _isLoading
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: c.appBarFg,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.login),
                    label: const Text('Googleでログイン'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: c.gold,
                      foregroundColor: c.appBarFg,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      textStyle: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // ── ゲストログインボタン ────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : _signInAsGuest,
                    icon: const Icon(Icons.person_outline),
                    label: const Text('ゲストで利用する'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.gold,
                      side: BorderSide(color: c.gold),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      textStyle: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // ── ゲスト利用の注意書き ────────────────────────
                Text(
                  '※ ゲストモードでは端末を変えるとデータを引き継げません',
                  style: TextStyle(fontSize: 11, color: c.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                // ── デモボタン ──────────────────────────────────
                // ゲストログイン＋モックの事件簿7日分を一括投入する
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: _isLoading ? null : _startDemo,
                    icon: const Icon(Icons.science_outlined, size: 18),
                    label: const Text('デモを見る（サンプルデータ投入）'),
                    style: TextButton.styleFrom(
                      foregroundColor: c.textSecondary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      textStyle: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
