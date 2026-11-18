import 'package:flutter/foundation.dart';
import '../../data/repositories/cognito_auth_repository.dart';
import '../../domain/models/cognito_auth.dart';
import '../../domain/models/profile_settings.dart';
import '../../domain/repositories/i_cognito_auth_repository.dart';
import '../../domain/repositories/i_profile_settings_repository.dart';

class SettingsProvider extends ChangeNotifier {
  final IProfileSettingsRepository _repository;
  final ICognitoAuthRepository _cognitoRepository;

  ProfileSettings _settings = ProfileSettings.defaults();
  CognitoConfig _cognitoConfig = CognitoConfig.defaults();
  CognitoAuthSession? _cognitoSession;

  bool _isLoaded = false;
  bool _isAuthenticating = false;
  String? _authError;
  bool _needsConfirmation = false;
  String? _pendingUsername;

  SettingsProvider({
    required IProfileSettingsRepository repository,
    ICognitoAuthRepository? cognitoRepository,
  }) : _repository = repository,
       _cognitoRepository = cognitoRepository ?? CognitoAuthRepository() {
    _load();
  }

  ProfileSettings get settings => _settings;
  CognitoConfig get cognitoConfig => _cognitoConfig;
  CognitoAuthSession? get cognitoSession => _cognitoSession;

  bool get isLoaded => _isLoaded;
  bool get isAuthenticating => _isAuthenticating;
  String? get authError => _authError;
  bool get needsConfirmation => _needsConfirmation;
  String? get pendingUsername => _pendingUsername;

  bool get isNocturneMode => _settings.isNocturneMode;
  bool get isAuthenticated => _settings.isAuthenticated;
  String get researcherName => _settings.researcherName;
  String get callSign => _settings.callSign;
  String get clearanceLevel => _settings.clearanceLevel;
  bool get isGuest => _settings.isGuest;

  void clearAuthError() {
    if (_authError != null) {
      _authError = null;
      notifyListeners();
    }
  }

  void resetConfirmationState() {
    _needsConfirmation = false;
    _pendingUsername = null;
    _authError = null;
    notifyListeners();
  }

  Future<void> _load() async {
    _settings = await _repository.loadSettings();
    _cognitoConfig = await _cognitoRepository.loadConfig();

    try {
      final savedSession = await _cognitoRepository.loadSavedSession();
      if (savedSession != null) {
        if (savedSession.isExpired &&
            savedSession.refreshToken != null &&
            _cognitoConfig.isConfigured) {
          try {
            _cognitoSession = await _cognitoRepository.refreshToken(
              refreshToken: savedSession.refreshToken!,
              username: savedSession.username,
              config: _cognitoConfig,
            );
            _settings = _settings.copyWith(
              apiKey: _cognitoSession!.accessToken,
              isAuthenticated: true,
              callSign: _cognitoSession!.username,
              researcherName:
                  _cognitoSession!.researcherName ?? _settings.researcherName,
              clearanceLevel:
                  _cognitoSession!.clearanceLevel ?? _settings.clearanceLevel,
            );
            await _repository.saveSettings(_settings);
          } catch (_) {
            _cognitoSession = savedSession;
          }
        } else {
          _cognitoSession = savedSession;
          if (_cognitoSession!.accessToken.isNotEmpty) {
            _settings = _settings.copyWith(
              apiKey: _cognitoSession!.accessToken,
              isAuthenticated: true,
              callSign:
                  _cognitoSession!.username.isNotEmpty
                      ? _cognitoSession!.username
                      : _settings.callSign,
              researcherName:
                  _cognitoSession!.researcherName ?? _settings.researcherName,
              clearanceLevel:
                  _cognitoSession!.clearanceLevel ?? _settings.clearanceLevel,
            );
            await _repository.saveSettings(_settings);
          }
        }
      }
    } catch (_) {}

    _isLoaded = true;
    notifyListeners();
  }

  /// Returns a valid, non-expired Cognito Access Token.
  /// Automatically refreshes the session via Amplify SRP or fallback refreshToken.
  Future<String?> getValidAccessToken() async {
    // Fast path: synchronous return if valid session or API key is active
    if (_cognitoSession != null && !_cognitoSession!.isExpired) {
      return _cognitoSession!.accessToken;
    }
    if (_settings.apiKey.isNotEmpty && !_settings.isGuest) {
      return _settings.apiKey;
    }

    try {
      final validToken = await _cognitoRepository.fetchValidAccessToken();
      if (validToken != null && validToken.isNotEmpty) {
        if (_settings.apiKey != validToken) {
          _settings = _settings.copyWith(
            apiKey: validToken,
            isAuthenticated: true,
          );
          await _repository.saveSettings(_settings);
          notifyListeners();
        }
        return validToken;
      }
    } catch (_) {}

    if (_cognitoSession == null) {
      return _settings.apiKey.isNotEmpty ? _settings.apiKey : null;
    }

    if (_cognitoSession!.isExpired &&
        _cognitoSession!.refreshToken != null &&
        _cognitoConfig.isConfigured) {
      try {
        final refreshed = await _cognitoRepository.refreshToken(
          refreshToken: _cognitoSession!.refreshToken!,
          username: _cognitoSession!.username,
          config: _cognitoConfig,
        );
        _cognitoSession = refreshed;
        _settings = _settings.copyWith(
          apiKey: refreshed.accessToken,
          isAuthenticated: true,
        );
        await _repository.saveSettings(_settings);
        notifyListeners();
        return refreshed.accessToken;
      } catch (_) {
        return _cognitoSession!.accessToken;
      }
    }

    return _cognitoSession!.accessToken;
  }

  Future<void> updateSettings(ProfileSettings newSettings) async {
    _settings = newSettings;
    notifyListeners();
    await _repository.saveSettings(newSettings);
  }

  Future<void> updateCognitoConfig(CognitoConfig config) async {
    _cognitoConfig = config;
    notifyListeners();
    await _cognitoRepository.saveConfig(config);
  }

  Future<void> toggleNocturneMode() async {
    final updated = _settings.copyWith(
      isNocturneMode: !_settings.isNocturneMode,
    );
    await updateSettings(updated);
  }

  Future<bool> signIn({
    required String callSign,
    required String passkey,
  }) async {
    _isAuthenticating = true;
    _authError = null;
    notifyListeners();

    try {
      final session = await _cognitoRepository.signIn(
        username: callSign.trim(),
        password: passkey,
        config: _cognitoConfig,
      );

      _cognitoSession = session;
      _needsConfirmation = false;
      _pendingUsername = null;

      final updated = _settings.copyWith(
        apiKey: session.accessToken,
        isAuthenticated: true,
        isGuest: false,
        callSign: session.username.isNotEmpty ? session.username : callSign,
        researcherName:
            session.researcherName ??
            (_settings.researcherName.isNotEmpty
                ? _settings.researcherName
                : 'Nithish R.'),
        clearanceLevel: session.clearanceLevel ?? _settings.clearanceLevel,
      );
      await updateSettings(updated);
      _isAuthenticating = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isAuthenticating = false;
      if (e is CognitoAuthException && e.code == 'UserNotConfirmedException') {
        _needsConfirmation = true;
        _pendingUsername = callSign.trim();
        _authError = 'Account unconfirmed. Please enter verification code.';
      } else {
        _authError = e.toString().replaceFirst('CognitoAuthException: ', '');
      }
      notifyListeners();
      return false;
    }
  }

  Future<bool> signUp({
    required String researcherName,
    required String callSign,
    required String clearanceLevel,
    required String passkey,
    String? email,
  }) async {
    _isAuthenticating = true;
    _authError = null;
    notifyListeners();

    final userEmail =
        email?.trim().isNotEmpty == true
            ? email!.trim()
            : '${callSign.trim().toLowerCase()}@synqra.ai';

    try {
      final isConfirmed = await _cognitoRepository.signUp(
        username: callSign.trim(),
        password: passkey,
        email: userEmail,
        researcherName: researcherName.trim(),
        clearanceLevel: clearanceLevel.trim(),
        config: _cognitoConfig,
      );

      if (!isConfirmed && _cognitoConfig.isConfigured) {
        _isAuthenticating = false;
        _needsConfirmation = true;
        _pendingUsername = callSign.trim();
        notifyListeners();
        return false;
      }

      // Automatically sign in once registered/confirmed
      final success = await signIn(callSign: callSign, passkey: passkey);
      return success;
    } catch (e) {
      _isAuthenticating = false;
      _authError = e.toString().replaceFirst('CognitoAuthException: ', '');
      notifyListeners();
      return false;
    }
  }

  Future<bool> confirmSignUp({
    required String confirmationCode,
    String? passkeyToAutoSignIn,
  }) async {
    if (_pendingUsername == null || _pendingUsername!.isEmpty) {
      _authError = 'No pending account to confirm';
      notifyListeners();
      return false;
    }

    _isAuthenticating = true;
    _authError = null;
    notifyListeners();

    try {
      await _cognitoRepository.confirmSignUp(
        username: _pendingUsername!,
        confirmationCode: confirmationCode.trim(),
        config: _cognitoConfig,
      );

      _needsConfirmation = false;

      if (passkeyToAutoSignIn != null && passkeyToAutoSignIn.isNotEmpty) {
        final success = await signIn(
          callSign: _pendingUsername!,
          passkey: passkeyToAutoSignIn,
        );
        return success;
      }

      _isAuthenticating = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isAuthenticating = false;
      _authError = e.toString().replaceFirst('CognitoAuthException: ', '');
      notifyListeners();
      return false;
    }
  }

  Future<void> resendConfirmationCode() async {
    if (_pendingUsername == null) return;
    try {
      await _cognitoRepository.resendConfirmationCode(
        username: _pendingUsername!,
        config: _cognitoConfig,
      );
      _authError = null;
      notifyListeners();
    } catch (e) {
      _authError = e.toString().replaceFirst('CognitoAuthException: ', '');
      notifyListeners();
    }
  }

  Future<bool> resetPassword({required String username}) async {
    _isAuthenticating = true;
    _authError = null;
    notifyListeners();

    try {
      await _cognitoRepository.resetPassword(
        username: username.trim(),
        config: _cognitoConfig,
      );
      _isAuthenticating = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isAuthenticating = false;
      _authError = e.toString().replaceFirst('CognitoAuthException: ', '');
      notifyListeners();
      return false;
    }
  }

  Future<bool> confirmResetPassword({
    required String username,
    required String newPassword,
    required String confirmationCode,
  }) async {
    _isAuthenticating = true;
    _authError = null;
    notifyListeners();

    try {
      await _cognitoRepository.confirmResetPassword(
        username: username.trim(),
        newPassword: newPassword,
        confirmationCode: confirmationCode.trim(),
        config: _cognitoConfig,
      );
      _isAuthenticating = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isAuthenticating = false;
      _authError = e.toString().replaceFirst('CognitoAuthException: ', '');
      notifyListeners();
      return false;
    }
  }

  Future<void> enterAsGuest() async {
    final updated = _settings.copyWith(
      isAuthenticated: true,
      isGuest: true,
      researcherName: 'Observer (Guest)',
      callSign: 'GUEST-OBSERVER',
      clearanceLevel: 'Level-1 Reader',
      apiKey: '',
    );
    await updateSettings(updated);
  }

  Future<bool> signInWithManagedLogin() async {
    _isAuthenticating = true;
    _authError = null;
    notifyListeners();

    try {
      final session = await _cognitoRepository.signInWithManagedLogin(
        config: _cognitoConfig,
      );

      _cognitoSession = session;
      _needsConfirmation = false;
      _pendingUsername = null;

      final updated = _settings.copyWith(
        apiKey: session.accessToken,
        isAuthenticated: true,
        isGuest: false,
        callSign:
            session.username.isNotEmpty ? session.username : 'ARCH-OPERATOR',
        researcherName: session.researcherName ?? _settings.researcherName,
        clearanceLevel: session.clearanceLevel ?? _settings.clearanceLevel,
      );
      await updateSettings(updated);
      _isAuthenticating = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isAuthenticating = false;
      _authError = e.toString().replaceFirst('CognitoAuthException: ', '');
      notifyListeners();
      return false;
    }
  }

  Future<void> signOutWithManagedLogin() async {
    final idToken = _cognitoSession?.idToken;
    await _cognitoRepository.signOutWithManagedLogin(
      idToken: idToken,
      config: _cognitoConfig,
    );
    _cognitoSession = null;
    final updated = _settings.copyWith(
      isAuthenticated: false,
      isGuest: false,
      apiKey: '',
    );
    await updateSettings(updated);
  }

  Future<void> signOut({bool clearBrowserSession = false}) async {
    try {
      if (clearBrowserSession && _cognitoSession != null) {
        await signOutWithManagedLogin();
      } else {
        await _cognitoRepository.signOut();
        _cognitoSession = null;
        final updated = _settings.copyWith(
          isAuthenticated: false,
          isGuest: false,
          apiKey: '',
        );
        await updateSettings(updated);
      }
    } catch (_) {
      _cognitoSession = null;
      final updated = _settings.copyWith(
        isAuthenticated: false,
        isGuest: false,
        apiKey: '',
      );
      await updateSettings(updated);
    }
  }
}
