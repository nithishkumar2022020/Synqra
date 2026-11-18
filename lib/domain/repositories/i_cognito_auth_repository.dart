import '../models/cognito_auth.dart';

abstract class ICognitoAuthRepository {
  Future<CognitoConfig> loadConfig();
  Future<void> saveConfig(CognitoConfig config);

  Future<CognitoAuthSession?> loadSavedSession();
  Future<void> saveSession(CognitoAuthSession session);
  Future<void> clearSession();

  // Legacy AppAuth Managed Login (kept for temporary compatibility)
  Future<CognitoAuthSession> signInWithManagedLogin({CognitoConfig? config});
  Future<void> signOutWithManagedLogin({
    String? idToken,
    CognitoConfig? config,
  });

  // Direct Cognito Authentication (Amplify Auth / SRP)
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

  Future<void> resetPassword({required String username, CognitoConfig? config});

  Future<void> confirmResetPassword({
    required String username,
    required String newPassword,
    required String confirmationCode,
    CognitoConfig? config,
  });

  Future<void> signOut();

  Future<CognitoAuthSession> refreshToken({
    required String refreshToken,
    required String username,
    CognitoConfig? config,
  });

  Future<String?> fetchValidAccessToken();
}
