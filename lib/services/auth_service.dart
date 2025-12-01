import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  // Singleton pattern
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  // Получить текущего пользователя
  User? get currentUser => _auth.currentUser;

  // Stream для отслеживания изменений состояния авторизации
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Вход через Email и пароль
  Future<UserCredential?> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return credential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw 'Произошла ошибка: ${e.toString()}';
    }
  }

  // Регистрация через Email и пароль
  Future<UserCredential?> signUpWithEmailAndPassword({
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      // Обновляем отображаемое имя
      if (credential.user != null && displayName.isNotEmpty) {
        await credential.user!.updateDisplayName(displayName);
        await credential.user!.reload();
      }

      return credential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw 'Произошла ошибка: ${e.toString()}';
    }
  }

  // Вход через Google
  Future<UserCredential?> signInWithGoogle() async {
    try {
      // Запускаем процесс входа в Google
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        // Пользователь отменил вход
        return null;
      }

      // Получаем данные аутентификации от Google
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // Создаем новый credential
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Входим в Firebase с Google credential
      return await _auth.signInWithCredential(credential);
    } catch (e) {
      throw 'Ошибка входа через Google: ${e.toString()}';
    }
  }

  // Восстановление пароля
  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw 'Произошла ошибка: ${e.toString()}';
    }
  }

  // Выход
  Future<void> signOut() async {
    try {
      await Future.wait([
        _auth.signOut(),
        _googleSignIn.signOut(),
      ]);
    } catch (e) {
      throw 'Ошибка выхода: ${e.toString()}';
    }
  }

  // Проверка, авторизован ли пользователь
  bool get isSignedIn => _auth.currentUser != null;

  // Обработка исключений Firebase Auth
  String _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'weak-password':
        return 'Пароль слишком слабый';
      case 'email-already-in-use':
        return 'Этот email уже используется';
      case 'user-not-found':
        return 'Пользователь с таким email не найден';
      case 'wrong-password':
        return 'Неверный пароль';
      case 'invalid-email':
        return 'Неверный формат email';
      case 'user-disabled':
        return 'Этот аккаунт был отключен';
      case 'too-many-requests':
        return 'Слишком много запросов. Попробуйте позже';
      case 'operation-not-allowed':
        return 'Эта операция не разрешена';
      case 'network-request-failed':
        return 'Ошибка сети. Проверьте подключение к интернету';
      default:
        return 'Ошибка авторизации: ${e.message ?? e.code}';
    }
  }
}
