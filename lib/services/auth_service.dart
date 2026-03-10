import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  Future<String?> signInAnonymously() async {
    final credential = await FirebaseAuth.instance.signInAnonymously();
    return credential.user?.uid;
  }
}
