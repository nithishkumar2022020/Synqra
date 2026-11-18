import 'dart:convert';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/models/cognito_auth.dart';
import '../../domain/repositories/i_cognito_auth_repository.dart';

class CognitoAuthException implements Exception {
  final String code;
  final String message;

  CognitoAuthException({required this.code, required this.message});

  @override
  String toString() => '$code: $message';
}

class CognitoAuthRepository implements ICognitoAuthRepository {
  static const _kConfigRegionKey = 'cognito_config_region';
  static const _kConfigPoolIdKey = 'cognito_config_user_pool_id';
  static const _kConfigClientIdKey = 'cognito_config_app_client_id';
  static const _kConfigDomainKey = 'cognito_config_domain';
  static const _kConfigCallbackUriKey = 'cognito_config_callback_uri';
  static const _kConfigEnabledKey = 'cognito_config_enabled';

  static const _kSecureSessionKey = 'cognito_secure_auth_session_v1';

  final FlutterAppAuth _appAuth;
  final FlutterSecureStorage _secureStorage;
  final http.Client? _injectedClient;

  // In-memory cache for fast synchronous access & mock fallback in unit tests
  final Map<String, String>? _memoryStorageFallback;

  CognitoAuthRepository({
    FlutterAppAuth? appAuth,
    FlutterSecureStorage? secureStorage,
    http.Client? client,
    Map<String, String>? memoryStorageFallback,
  }) : _appAuth = appAuth ?? const FlutterAppAuth(),
       _secureStorage =
           secureStorage ??
           const FlutterSecureStorage(
             aOptions: AndroidOptions(resetOnError: true),
           ),
       _injectedClient = client,
       _memoryStorageFallback = memoryStorageFallback;

  http.Client _getClient() => _injectedClient ?? http.Client();

  @override
  Future<CognitoConfig> loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final defaults = CognitoConfig.defaults();
      return CognitoConfig(
        region: prefs.getString(_kConfigRegionKey) ?? defaults.region,
        userPoolId: prefs.getString(_kConfigPoolIdKey) ?? defaults.userPoolId,
        appClientId:
            prefs.getString(_kConfigClientIdKey) ?? defaults.appClientId,
        cognitoDomain:
            prefs.getString(_kConfigDomainKey) ?? defaults.cognitoDomain,
        callbackUri:
            prefs.getString(_kConfigCallbackUriKey) ?? defaults.callbackUri,
        scopes: defaults.scopes,
        isEnabled: prefs.getBool(_kConfigEnabledKey) ?? defaults.isEnabled,
      );
    } catch (_) {
      return CognitoConfig.defaults();
    }
  }

  @override
  Future<void> saveConfig(CognitoConfig config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kConfigRegionKey, config.region.trim());
      await prefs.setString(_kConfigPoolIdKey, config.userPoolId.trim());
      await prefs.setString(_kConfigClientIdKey, config.appClientId.trim());
      await prefs.setString(_kConfigDomainKey, config.cognitoDomain.trim());
      await prefs.setString(_kConfigCallbackUriKey, config.callbackUri.trim());
      await prefs.setBool(_kConfigEnabledKey, config.isEnabled);
    } catch (_) {}
  }

  @override
  Future<CognitoAuthSession?> loadSavedSession() async {
    try {
      if (_memoryStorageFallback != null) {
        final raw = _memoryStorageFallback[_kSecureSessionKey];
        if (raw == null || raw.isEmpty) return null;
        return CognitoAuthSession.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      }
      final raw = await _secureStorage.read(key: _kSecureSessionKey);
      if (raw == null || raw.isEmpty) return null;
      final json = jsonDecode(raw);
      if (json is Map<String, dynamic>) {
        return CognitoAuthSession.fromJson(json);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveSession(CognitoAuthSession session) async {
    try {
      final jsonStr = jsonEncode(session.toJson());
      if (_memoryStorageFallback != null) {
        _memoryStorageFallback[_kSecureSessionKey] = jsonStr;
        return;
      }
      await _secureStorage.write(key: _kSecureSessionKey, value: jsonStr);
    } catch (_) {}
  }

  @override
  Future<void> clearSession() async {
    try {
      if (_memoryStorageFallback != null) {
        _memoryStorageFallback.remove(_kSecureSessionKey);
        return;
      }
      await _secureStorage.delete(key: _kSecureSessionKey);
    } catch (_) {}
  }

  @override
  Future<CognitoAuthSession> signInWithManagedLogin({
    CognitoConfig? config,
  }) async {
    final activeConfig = config ?? await loadConfig();

    try {
      AuthorizationTokenResponse result;
      try {
        // Primary flow: Use Cognito's OIDC discovery configuration (.well-known/openid-configuration)
        result = await _appAuth.authorizeAndExchangeCode(
          AuthorizationTokenRequest(
            activeConfig.appClientId,
            activeConfig.callbackUri,
            discoveryUrl: activeConfig.discoveryUrl,
            issuer: activeConfig.issuer,
            scopes: activeConfig.scopes,
            promptValues: const ['login'],
          ),
        );
      } catch (_) {
        // Fallback: Use direct service configuration if OIDC discovery is unavailable
        final serviceConfiguration = AuthorizationServiceConfiguration(
          authorizationEndpoint: activeConfig.authorizationEndpoint,
          tokenEndpoint: activeConfig.tokenEndpoint,
          endSessionEndpoint: activeConfig.endSessionEndpoint,
        );
        result = await _appAuth.authorizeAndExchangeCode(
          AuthorizationTokenRequest(
            activeConfig.appClientId,
            activeConfig.callbackUri,
            serviceConfiguration: serviceConfiguration,
            scopes: activeConfig.scopes,
            promptValues: const ['login'],
          ),
        );
      }

      if (result.accessToken == null || result.accessToken!.isEmpty) {
        throw CognitoAuthException(
          code: 'AuthenticationFailed',
          message: 'Cognito Managed Login did not return an access token.',
        );
      }

      final accessToken = result.accessToken!;
      final idToken = result.idToken;
      final refreshToken = result.refreshToken;
      final expiresAt =
          result.accessTokenExpirationDateTime ??
          DateTime.now().add(const Duration(hours: 1));

      String username = 'ARCH-OPERATOR';
      String? researcherName;
      String? clearanceLevel;
      String? email;

      if (idToken != null) {
        final claims = CognitoAuthSession.decodeJwtPayload(idToken);
        username =
            claims['cognito:username']?.toString() ??
            claims['preferred_username']?.toString() ??
            claims['sub']?.toString() ??
            username;
        researcherName =
            claims['name']?.toString() ??
            claims['given_name']?.toString() ??
            username;
        clearanceLevel =
            claims['custom:clearance']?.toString() ?? 'Level-3 Architect';
        email = claims['email']?.toString();
      } else {
        final accessClaims = CognitoAuthSession.decodeJwtPayload(accessToken);
        username = accessClaims['username']?.toString() ?? username;
      }

      final session = CognitoAuthSession(
        accessToken: accessToken,
        idToken: idToken,
        refreshToken: refreshToken,
        expiresAt: expiresAt,
        username: username,
        researcherName: researcherName,
        clearanceLevel: clearanceLevel,
        email: email,
      );

      await saveSession(session);
      return session;
    } catch (e) {
      if (e is CognitoAuthException) rethrow;
      throw CognitoAuthException(
        code: 'ManagedLoginError',
        message: 'Managed login failed: $e',
      );
    }
  }

  @override
  Future<void> signOutWithManagedLogin({
    String? idToken,
    CognitoConfig? config,
  }) async {
    final activeConfig = config ?? await loadConfig();

    try {
      try {
        // Primary flow: Use Cognito's OIDC discovery for end_session_endpoint
        await _appAuth.endSession(
          EndSessionRequest(
            idTokenHint:
                (idToken != null && idToken.isNotEmpty) ? idToken : null,
            postLogoutRedirectUrl: activeConfig.callbackUri,
            discoveryUrl: activeConfig.discoveryUrl,
            issuer: activeConfig.issuer,
          ),
        );
      } catch (_) {
        // Fallback: Direct service configuration
        final serviceConfiguration = AuthorizationServiceConfiguration(
          authorizationEndpoint: activeConfig.authorizationEndpoint,
          tokenEndpoint: activeConfig.tokenEndpoint,
          endSessionEndpoint: activeConfig.endSessionEndpoint,
        );

        await _appAuth.endSession(
          EndSessionRequest(
            idTokenHint:
                (idToken != null && idToken.isNotEmpty) ? idToken : null,
            postLogoutRedirectUrl: activeConfig.callbackUri,
            serviceConfiguration: serviceConfiguration,
          ),
        );
      }
    } catch (_) {
      // Browser dismiss or cancellation still clears local session
    } finally {
      await clearSession();
    }
  }

  Future<Map<String, dynamic>> _callCognitoApi({
    required CognitoConfig config,
    required String action,
    required Map<String, dynamic> payload,
  }) async {
    final client = _getClient();
    final uri = Uri.parse(config.endpoint);

    final request = http.Request('POST', uri);
    request.headers['Content-Type'] = 'application/x-amz-json-1.1';
    request.headers['X-Amz-Target'] =
        'AWSCognitoIdentityProviderService.$action';
    request.body = jsonEncode(payload);

    try {
      final streamed = await client
          .send(request)
          .timeout(const Duration(seconds: 15));
      final respBytes = await streamed.stream.toBytes();
      final bodyStr = utf8.decode(respBytes, allowMalformed: true);

      if (streamed.statusCode >= 200 && streamed.statusCode < 300) {
        if (bodyStr.isEmpty) return {};
        return jsonDecode(bodyStr) as Map<String, dynamic>;
      }

      String errorCode = 'CognitoError';
      String errorMessage = 'Cognito request failed (${streamed.statusCode})';

      try {
        final errJson = jsonDecode(bodyStr);
        if (errJson is Map) {
          final rawType = errJson['__type']?.toString() ?? '';
          errorCode = rawType.split('#').last;
          errorMessage =
              errJson['message']?.toString() ??
              errJson['Message']?.toString() ??
              errorMessage;
        }
      } catch (_) {}

      throw CognitoAuthException(code: errorCode, message: errorMessage);
    } finally {
      if (_injectedClient == null) {
        client.close();
      }
    }
  }

  @override
  Future<CognitoAuthSession> signIn({
    required String username,
    required String password,
    CognitoConfig? config,
  }) async {
    final activeConfig = config ?? await loadConfig();

    if (!activeConfig.isConfigured) {
      return CognitoAuthSession(
        accessToken: 'cognito_dev_${DateTime.now().millisecondsSinceEpoch}',
        idToken: null,
        refreshToken: 'mock_refresh_token',
        expiresAt: DateTime.now().add(const Duration(hours: 8)),
        username: username,
        researcherName: username,
        clearanceLevel: 'Level-3 Architect',
      );
    }

    final response = await _callCognitoApi(
      config: activeConfig,
      action: 'InitiateAuth',
      payload: {
        'AuthFlow': 'USER_PASSWORD_AUTH',
        'ClientId': activeConfig.appClientId,
        'AuthParameters': {'USERNAME': username.trim(), 'PASSWORD': password},
      },
    );

    final authResult =
        response['AuthenticationResult'] as Map<String, dynamic>?;
    if (authResult == null) {
      final challenge = response['ChallengeName']?.toString();
      throw CognitoAuthException(
        code: challenge ?? 'ChallengeRequired',
        message: 'Authentication challenge: ${challenge ?? 'unknown'}',
      );
    }

    final accessToken = authResult['AccessToken']?.toString() ?? '';
    final idToken = authResult['IdToken']?.toString();
    final refreshToken = authResult['RefreshToken']?.toString();
    final expiresIn =
        authResult['ExpiresIn'] is int
            ? authResult['ExpiresIn'] as int
            : int.tryParse(authResult['ExpiresIn']?.toString() ?? '3600') ??
                3600;

    String? researcherName;
    String? clearanceLevel;
    String? email;

    if (idToken != null) {
      final claims = CognitoAuthSession.decodeJwtPayload(idToken);
      researcherName =
          claims['name']?.toString() ?? claims['given_name']?.toString();
      clearanceLevel = claims['custom:clearance']?.toString();
      email = claims['email']?.toString();
    }

    final session = CognitoAuthSession(
      accessToken: accessToken,
      idToken: idToken,
      refreshToken: refreshToken,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
      username: username.trim(),
      researcherName: researcherName,
      clearanceLevel: clearanceLevel,
      email: email,
    );

    await saveSession(session);
    return session;
  }

  @override
  Future<bool> signUp({
    required String username,
    required String password,
    required String email,
    String? researcherName,
    String? clearanceLevel,
    CognitoConfig? config,
  }) async {
    final activeConfig = config ?? await loadConfig();

    if (!activeConfig.isConfigured) {
      return true;
    }

    final userAttrs = <Map<String, String>>[
      {'Name': 'email', 'Value': email.trim()},
    ];
    if (researcherName != null && researcherName.trim().isNotEmpty) {
      userAttrs.add({'Name': 'name', 'Value': researcherName.trim()});
    }
    if (clearanceLevel != null && clearanceLevel.trim().isNotEmpty) {
      userAttrs.add({
        'Name': 'custom:clearance',
        'Value': clearanceLevel.trim(),
      });
    }

    final response = await _callCognitoApi(
      config: activeConfig,
      action: 'SignUp',
      payload: {
        'ClientId': activeConfig.appClientId,
        'Username': username.trim(),
        'Password': password,
        'UserAttributes': userAttrs,
      },
    );

    final isConfirmed = response['UserConfirmed'] == true;
    return isConfirmed;
  }

  @override
  Future<void> confirmSignUp({
    required String username,
    required String confirmationCode,
    CognitoConfig? config,
  }) async {
    final activeConfig = config ?? await loadConfig();
    if (!activeConfig.isConfigured) return;

    await _callCognitoApi(
      config: activeConfig,
      action: 'ConfirmSignUp',
      payload: {
        'ClientId': activeConfig.appClientId,
        'Username': username.trim(),
        'ConfirmationCode': confirmationCode.trim(),
      },
    );
  }

  @override
  Future<void> resendConfirmationCode({
    required String username,
    CognitoConfig? config,
  }) async {
    final activeConfig = config ?? await loadConfig();
    if (!activeConfig.isConfigured) return;

    await _callCognitoApi(
      config: activeConfig,
      action: 'ResendConfirmationCode',
      payload: {
        'ClientId': activeConfig.appClientId,
        'Username': username.trim(),
      },
    );
  }

  @override
  Future<CognitoAuthSession> refreshToken({
    required String refreshToken,
    required String username,
    CognitoConfig? config,
  }) async {
    final activeConfig = config ?? await loadConfig();

    try {
      // First try refreshing via AppAuth TokenRequest with OIDC discovery
      TokenResponse tokenResult;
      try {
        tokenResult = await _appAuth.token(
          TokenRequest(
            activeConfig.appClientId,
            activeConfig.callbackUri,
            refreshToken: refreshToken,
            discoveryUrl: activeConfig.discoveryUrl,
            issuer: activeConfig.issuer,
            scopes: activeConfig.scopes,
          ),
        );
      } catch (_) {
        final serviceConfiguration = AuthorizationServiceConfiguration(
          authorizationEndpoint: activeConfig.authorizationEndpoint,
          tokenEndpoint: activeConfig.tokenEndpoint,
          endSessionEndpoint: activeConfig.endSessionEndpoint,
        );
        tokenResult = await _appAuth.token(
          TokenRequest(
            activeConfig.appClientId,
            activeConfig.callbackUri,
            refreshToken: refreshToken,
            serviceConfiguration: serviceConfiguration,
            scopes: activeConfig.scopes,
          ),
        );
      }

      if (tokenResult.accessToken != null &&
          tokenResult.accessToken!.isNotEmpty) {
        final existingSession = await loadSavedSession();
        final updated = CognitoAuthSession(
          accessToken: tokenResult.accessToken!,
          idToken: tokenResult.idToken ?? existingSession?.idToken,
          refreshToken: tokenResult.refreshToken ?? refreshToken,
          expiresAt:
              tokenResult.accessTokenExpirationDateTime ??
              DateTime.now().add(const Duration(hours: 1)),
          username: username,
          researcherName: existingSession?.researcherName,
          clearanceLevel: existingSession?.clearanceLevel,
          email: existingSession?.email,
        );
        await saveSession(updated);
        return updated;
      }
    } catch (_) {
      // Fallback to direct REST API
    }

    final response = await _callCognitoApi(
      config: activeConfig,
      action: 'InitiateAuth',
      payload: {
        'AuthFlow': 'REFRESH_TOKEN_AUTH',
        'ClientId': activeConfig.appClientId,
        'AuthParameters': {'REFRESH_TOKEN': refreshToken},
      },
    );

    final authResult =
        response['AuthenticationResult'] as Map<String, dynamic>?;
    if (authResult == null) {
      throw CognitoAuthException(
        code: 'RefreshFailed',
        message: 'Could not refresh Cognito token',
      );
    }

    final newAccessToken = authResult['AccessToken']?.toString() ?? '';
    final newIdToken = authResult['IdToken']?.toString();
    final expiresIn =
        authResult['ExpiresIn'] is int
            ? authResult['ExpiresIn'] as int
            : int.tryParse(authResult['ExpiresIn']?.toString() ?? '3600') ??
                3600;

    final existingSession = await loadSavedSession();

    final updated = CognitoAuthSession(
      accessToken: newAccessToken,
      idToken: newIdToken ?? existingSession?.idToken,
      refreshToken: refreshToken,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
      username: username,
      researcherName: existingSession?.researcherName,
      clearanceLevel: existingSession?.clearanceLevel,
      email: existingSession?.email,
    );

    await saveSession(updated);
    return updated;
  }
}
