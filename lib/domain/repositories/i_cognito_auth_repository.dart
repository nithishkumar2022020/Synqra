import '../models/cognito_auth.dart';

abstract class ICognitoAuthRepository {
  Future<CognitoConfig> loadConfig();
  Future<void> saveConfig(CognitoConfig config);

  Future<CognitoAuthSession?> loadSavedSession();
  Future<void> saveSession(CognitoAuthSession session);
  Future<void> clearSession();

  Future<CognitoAuthSession> signInWithManagedLogin({CognitoConfig? config});

  Future<void> signOutWithManagedLogin({
    String? idToken,
    CognitoConfig? config,
  });

  Future<CognitoAuthSession> signIn({
    required String username,
    required String password,
    CognitoConfig? config,
  });

  Future<bool> signUp({
    required String username,
    required String password,
    required String email,
    String? researcherName,
    String? clearanceLevel,
    CognitoConfig? config,
  });

  Future<void> confirmSignUp({
    required String username,
    required String confirmationCode,
    CognitoConfig? config,
  });

  Future<void> resendConfirmationCode({
    required String username,
    CognitoConfig? config,
  });

  Future<CognitoAuthSession> refreshToken({
    required String refreshToken,
    required String username,
    CognitoConfig? config,
  });
}
