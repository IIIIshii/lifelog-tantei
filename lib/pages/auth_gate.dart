import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../services/auth_service.dart';
import 'home_page.dart';
import 'login_page.dart';

// 認証状態に応じて LoginPage / HomePage を切り替えるゲート。
// 各ページが個別に匿名サインインを呼ぶ運用を廃止し、認証フローをここに集約する。
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _AuthLoadingScaffold();
        }
        if (snapshot.data == null) {
          return const LoginPage();
        }
        return const HomePage();
      },
    );
  }
}

class _AuthLoadingScaffold extends StatelessWidget {
  const _AuthLoadingScaffold();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: Center(child: CircularProgressIndicator(color: c.gold)),
    );
  }
}
