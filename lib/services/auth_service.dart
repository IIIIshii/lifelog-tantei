import 'package:firebase_auth/firebase_auth.dart';

// Firebase匿名認証を担当するサービスクラス
class AuthService {
  // 匿名サインインを行い、ユーザーのUIDを返す
  Future<String?> signInAnonymously() async {
    final credential = await FirebaseAuth.instance.signInAnonymously();
    return credential.user?.uid;
  }
}
