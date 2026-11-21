import 'package:flutter/foundation.dart';
import '../../core/services/cloudwatch_service.dart';
import '../../data/repositories/cognito_auth_repository.dart';
import '../../domain/models/cognito_auth.dart';
import '../../domain/models/profile_settings.dart';
import '../../domain/repositories/i_cognito_auth_repository.dart';
import '../../domain/repositories/i_profile_settings_repository.dart';

class SettingsProvider extends ChangeNotifier {
  final IProfileSettingsRepository _repository;
  final ICognitoAuthRepository _cognitoRepository;
  final CloudWatchService? _cloudWatchService;

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
    CloudWatchService? cloudWatchService,
  }) : _repository = repository,
       _cognitoRepository = cognitoRepository ?? CognitoAuthRepository(),
       _cloudWatchService = cloudWatchService {
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

  /// Detects whether a string is a raw user ID (such as a Cognito sub UUID or hex identifier)
  /// rather than a human-readable name or call sign.
  static bool isUserId(String? text) {
    if (text == null) return false;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    // Standard UUID pattern (8-4-4-4-12 hex)
    final uuidRegex = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    if (uuidRegex.hasMatch(trimmed)) return true;
    // 32-character continuous hex hash
    if (RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(trimmed)) return true;
    // AWS Cognito pool or sub prefixes
    if (trimmed.startsWith('ap-southeast-2_') ||
        trimmed.startsWith('us-east-1_') ||
        trimmed.startsWith('eu-west-1_')) {
      return true;
    }
    return false;
  }

  /// Formats an email address into a human-readable name (e.g. nithishkumarreddy@gmail.com -> Nithish Kumar Reddy).
  static String formatNameFromEmail(String email) {
    final prefix = email.split('@').first;
    final words = prefix
        .replaceAll(RegExp(r'[._\-]'), ' ')
        .trim()
        .split(RegExp(r'\s+'));
    final formatted = words
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
        .join(' ');
    return formatted.isNotEmpty ? formatted : 'Researcher';
  }

  /// Clean display name for the current operator, guaranteed to never show raw Cognito UUIDs or user IDs.
  String get displayName {
    if (isGuest) return 'Observer (Guest)';

    // 1. Session researcher name if valid and not a UUID
    final sessionName = _cognitoSession?.researcherName?.trim();
    if (sessionName != null &&
        sessionName.isNotEmpty &&
        !isUserId(sessionName)) {
      return sessionName;
    }

    // 2. Saved settings researcher name if valid and not a UUID
    final settingName = _settings.researcherName.trim();
    if (settingName.isNotEmpty && !isUserId(settingName)) {
      return settingName;
    }

    // 3. Fallback to extracting from Cognito email
    final email = _cognitoSession?.email?.trim();
    if (email != null && email.contains('@')) {
      return formatNameFromEmail(email);
    }

    return 'Dr. Nithish R.';
  }

  /// Clean call sign for the current operator, guaranteed to never show raw Cognito UUIDs or user IDs.
  String get displayCallSign {
    if (isGuest) return 'GUEST-OBSERVER';

    final sign = _settings.callSign.trim();
    if (sign.isNotEmpty && !isUserId(sign)) {
      return sign;
    }

    return 'ARCH-9942';
  }

  /// Initials derived from the clean display name.
  String get displayInitials {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    if (parts.length > 1 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    if (displayName.isNotEmpty) {
      return displayName
          .substring(0, displayName.length >= 2 ? 2 : 1)
          .toUpperCase();
    }
    return 'NR';
  }

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
    if (_cloudWatchService != null) {
      _cloudWatchService.isEnabled = _settings.enableCloudWatch;
    }

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
            final sessionUsername = _cognitoSession!.username;
            final resolvedCallSign =
                isUserId(sessionUsername)
                    ? _settings.callSign
                    : sessionUsername;
            final sessionResearcher = _cognitoSession!.researcherName;
            final resolvedResearcher =
                (sessionResearcher != null && !isUserId(sessionResearcher))
                    ? sessionResearcher
                    : (_cognitoSession!.email != null &&
                            _cognitoSession!.email!.contains('@')
                        ? formatNameFromEmail(_cognitoSession!.email!)
                        : _settings.researcherName);

            _settings = _settings.copyWith(
              apiKey: _cognitoSession!.accessToken,
              isAuthenticated: true,
              callSign: resolvedCallSign,
              researcherName: resolvedResearcher,
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
            final sessionUsername = _cognitoSession!.username;
            final resolvedCallSign =
                isUserId(sessionUsername)
                    ? _settings.callSign
                    : (sessionUsername.isNotEmpty
                        ? sessionUsername
                        : _settings.callSign);
            final sessionResearcher = _cognitoSession!.researcherName;
            final resolvedResearcher =
                (sessionResearcher != null && !isUserId(sessionResearcher))
                    ? sessionResearcher
                    : (_cognitoSession!.email != null &&
                            _cognitoSession!.email!.contains('@')
                        ? formatNameFromEmail(_cognitoSession!.email!)
                        : _settings.researcherName);

            _settings = _settings.copyWith(
              apiKey: _cognitoSession!.accessToken,
              isAuthenticated: true,
              callSign: resolvedCallSign,
              researcherName: resolvedResearcher,
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

      final sessionUsername = session.username;
      final resolvedCallSign =
          isUserId(sessionUsername)
              ? (!isUserId(callSign) && callSign.trim().isNotEmpty
                  ? callSign.trim()
                  : _settings.callSign)
              : (sessionUsername.isNotEmpty ? sessionUsername : callSign);
      final sessionResearcher = session.researcherName;
      final resolvedResearcher =
          (sessionResearcher != null && !isUserId(sessionResearcher))
              ? sessionResearcher
              : (session.email != null && session.email!.contains('@')
                  ? formatNameFromEmail(session.email!)
                  : (_settings.researcherName.isNotEmpty &&
                          !isUserId(_settings.researcherName)
                      ? _settings.researcherName
                      : 'Nithish R.'));

      final updated = _settings.copyWith(
        apiKey: session.accessToken,
        isAuthenticated: true,
        isGuest: false,
        callSign: resolvedCallSign,
        researcherName: resolvedResearcher,
        clearanceLevel: session.clearanceLevel ?? _settings.clearanceLevel,
      );
      await updateSettings(updated);
      _cloudWatchService?.logAuth(
        action: 'SIGN_IN',
        callSign: resolvedCallSign,
        isSuccess: true,
        detail: 'Clearance: ${session.clearanceLevel ?? _settings.clearanceLevel}',
      );
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
      _cloudWatchService?.logAuth(
        action: 'SIGN_IN',
        callSign: callSign.trim(),
        isSuccess: false,
        detail: _authError,
      );
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
    _cloudWatchService?.logAuth(
      action: 'GUEST_ENTRY',
      callSign: 'GUEST-OBSERVER',
      isSuccess: true,
    );
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

      final sessionUsername = session.username;
      final resolvedCallSign =
          isUserId(sessionUsername)
              ? _settings.callSign
              : (sessionUsername.isNotEmpty
                  ? sessionUsername
                  : 'ARCH-OPERATOR');
      final sessionResearcher = session.researcherName;
      final resolvedResearcher =
          (sessionResearcher != null && !isUserId(sessionResearcher))
              ? sessionResearcher
              : (session.email != null && session.email!.contains('@')
                  ? formatNameFromEmail(session.email!)
                  : _settings.researcherName);

      final updated = _settings.copyWith(
        apiKey: session.accessToken,
        isAuthenticated: true,
        isGuest: false,
        callSign: resolvedCallSign,
        researcherName: resolvedResearcher,
        clearanceLevel: session.clearanceLevel ?? _settings.clearanceLevel,
      );
      await updateSettings(updated);
      _cloudWatchService?.logAuth(
        action: 'MANAGED_LOGIN_SUCCESS',
        callSign: resolvedCallSign,
        isSuccess: true,
      );
      _isAuthenticating = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isAuthenticating = false;
      _authError = e.toString().replaceFirst('CognitoAuthException: ', '');
      _cloudWatchService?.logAuth(
        action: 'MANAGED_LOGIN_FAILURE',
        callSign: _settings.callSign,
        isSuccess: false,
        detail: _authError,
      );
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
    _cloudWatchService?.logAuth(
      action: 'SIGN_OUT',
      callSign: _settings.callSign,
      isSuccess: true,
    );
  }

  Future<void> signOut({bool clearBrowserSession = false}) async {
    try {
      await _cognitoRepository.signOut();
    } catch (_) {}
    _cognitoSession = null;
    final updated = _settings.copyWith(
      isAuthenticated: false,
      isGuest: false,
      apiKey: '',
    );
    await updateSettings(updated);
    _cloudWatchService?.logAuth(
      action: 'SIGN_OUT',
      callSign: _settings.callSign,
      isSuccess: true,
    );
  }

  Future<void> setCloudWatchEnabled(bool enabled) async {
    final updated = _settings.copyWith(enableCloudWatch: enabled);
    if (_cloudWatchService != null) {
      _cloudWatchService.isEnabled = enabled;
    }
    await updateSettings(updated);
  }

  Future<void> setCloudWatchConfig({String? logGroup, String? region}) async {
    final updated = _settings.copyWith(
      cloudWatchLogGroup: logGroup ?? _settings.cloudWatchLogGroup,
      cloudWatchRegion: region ?? _settings.cloudWatchRegion,
    );
    await updateSettings(updated);
  }
}
