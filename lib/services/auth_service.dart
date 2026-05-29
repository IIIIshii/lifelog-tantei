import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';

// 認証ハブ：Google サインインと匿名（ゲスト）サインインを一元管理する。
// AuthGate からは authStateChanges を購読し、ログイン状態を起動フローに反映させる。
//
// GoogleSignIn 7.x は `initialize()` を一度だけ呼ぶ必要があり、`authenticate()` で
// アカウント取得 → ID トークンを GoogleAuthProvider に渡して FirebaseAuth に通す
// という流れになっている。古い `GoogleSignIn().signIn()` API は使えない。
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _googleInitialized = false;

  // GoogleSignIn の初期化は一度きり。Web は clientId、ネイティブは serverClientId に
  // Firebase の "Web client ID" を渡すと Firebase Auth が受け取れる ID トークンが得られる。
  // .env に GOOGLE_WEB_CLIENT_ID が無ければ null で渡す（プラットフォーム既定の動作）。
  Future<void> _ensureGoogleInitialized() async {
    if (_googleInitialized) return;
    final webClientId = dotenv.env['GOOGLE_WEB_CLIENT_ID'];
    // serverClientId（FirebaseのWebクライアントID）が無いと、Androidでは
    // idToken が取得できず Firebase 認証に通せない。早期に分かりやすく失敗させる。
    if ((webClientId == null || webClientId.isEmpty)) {
      throw StateError(
        'GOOGLE_WEB_CLIENT_ID が .env に設定されていません。'
        'Firebase の Web クライアントID（google-services.json の client_type:3）を設定してください。',
      );
    }
    await GoogleSignIn.instance.initialize(
      clientId: kIsWeb ? webClientId : null,
      serverClientId: !kIsWeb ? webClientId : null,
    );
    _googleInitialized = true;
  }

  Stream<User?> authStateChanges() => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<User?> signInWithGoogle() async {
    await _ensureGoogleInitialized();
    final account = await GoogleSignIn.instance.authenticate();
    final auth = account.authentication;
    final idToken = auth.idToken;
    // idToken が null の場合、SHA-1 未登録 / serverClientId 不一致などが疑われる。
    // ここで握り潰すと GoogleAuthProvider.credential が分かりにくく失敗するため明示的に弾く。
    if (idToken == null) {
      throw StateError(
        'Google から idToken を取得できませんでした。'
        'Firebase に SHA-1 指紋が登録されているか、GOOGLE_WEB_CLIENT_ID が正しいか確認してください。',
      );
    }
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    final userCred = await _auth.signInWithCredential(credential);
    return userCred.user;
  }

  Future<User?> signInAsGuest() async {
    final userCred = await _auth.signInAnonymously();
    return userCred.user;
  }

  // disconnect は次回ログイン時に再度アカウント選択ダイアログを出すために使う。
  // 一度も Google にログインしていない場合は例外になり得るため握り潰す。
  Future<void> signOut() async {
    if (_googleInitialized) {
      try {
        await GoogleSignIn.instance.disconnect();
      } catch (_) {
        // 未認可・既切断などは無視
      }
    }
    await _auth.signOut();
  }
}
