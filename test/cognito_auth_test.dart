import 'dart:convert';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_flutter_proj_dq/core/network/authenticated_http_client.dart';
import 'package:my_flutter_proj_dq/data/repositories/cognito_auth_repository.dart';
import 'package:my_flutter_proj_dq/data/repositories/profile_settings_repository.dart';
import 'package:my_flutter_proj_dq/domain/models/cognito_auth.dart';
import 'package:my_flutter_proj_dq/presentation/providers/settings_provider.dart';

class FakeFlutterAppAuth extends Fake implements FlutterAppAuth {
  final AuthorizationTokenResponse mockAuthResponse;
  final TokenResponse mockTokenResponse;
  bool endSessionCalled = false;

  FakeFlutterAppAuth({
    AuthorizationTokenResponse? mockAuthResponse,
    TokenResponse? mockTokenResponse,
  }) : mockAuthResponse =
           mockAuthResponse ??
           AuthorizationTokenResponse(
             'default_access',
             'default_refresh',
             DateTime.now().add(const Duration(hours: 1)),
             null,
             'Bearer',
             const ['openid'],
             null,
             null,
           ),
       mockTokenResponse =
           mockTokenResponse ??
           TokenResponse(
             'default_refreshed_access',
             'default_refresh',
             DateTime.now().add(const Duration(hours: 1)),
             null,
             'Bearer',
             const ['openid'],
             null,
           );

  @override
  Future<AuthorizationTokenResponse> authorizeAndExchangeCode(
    AuthorizationTokenRequest request,
  ) async {
    return mockAuthResponse;
  }

  @override
  Future<TokenResponse> token(TokenRequest request) async {
    return mockTokenResponse;
  }

  @override
  Future<EndSessionResponse> endSession(EndSessionRequest request) async {
    endSessionCalled = true;
    return EndSessionResponse(null);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  final testConfig = const CognitoConfig(
    region: 'ap-southeast-2',
    userPoolId: 'ap-southeast-2_cR0iLu56D',
    appClientId: '4p3oehrll2pd9p1ann0gvubp1c',
    cognitoDomain:
        'https://ap-southeast-2cr0ilu56d.auth.ap-southeast-2.amazoncognito.com',
    callbackUri: 'com.example.synqra://auth/callback',
    scopes: ['openid', 'email'],
    isEnabled: true,
  );

  group('CognitoAuthRepository Unit Tests', () {
    test(
      'InitiateAuth (USER_PASSWORD_AUTH) signs in and parses token',
      () async {
        late String capturedTarget;
        late String capturedContentType;
        late Map<String, dynamic> capturedBody;

        final header = base64Url.encode(
          utf8.encode(jsonEncode({'alg': 'RS256'})),
        );
        final payload = base64Url.encode(
          utf8.encode(
            jsonEncode({
              'sub': 'user-uuid-1234',
              'name': 'Dr. Nithish R.',
              'custom:clearance': 'Level-3 Architect',
              'email': 'nithish@synqra.ai',
            }),
          ),
        );
        final dummyIdToken = '$header.$payload.dummySignature';

        final mockClient = MockClient((request) async {
          capturedTarget = request.headers['X-Amz-Target'] ?? '';
          capturedContentType = request.headers['Content-Type'] ?? '';
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;

          return http.Response(
            jsonEncode({
              'AuthenticationResult': {
                'AccessToken': 'cognito_access_jwt_valid',
                'IdToken': dummyIdToken,
                'RefreshToken': 'cognito_refresh_jwt_valid',
                'ExpiresIn': 3600,
                'TokenType': 'Bearer',
              },
            }),
            200,
            headers: {'content-type': 'application/x-amz-json-1.1'},
          );
        });

        final memoryStorage = <String, String>{};
        final repo = CognitoAuthRepository(
          client: mockClient,
          memoryStorageFallback: memoryStorage,
        );
        final session = await repo.signIn(
          username: 'ARCH-9942',
          password: 'Passkey_1234!@#',
          config: testConfig,
        );

        expect(
          capturedTarget,
          'AWSCognitoIdentityProviderService.InitiateAuth',
        );
        expect(capturedContentType, contains('application/x-amz-json-1.1'));
        expect(capturedBody['AuthFlow'], 'USER_PASSWORD_AUTH');
        expect(capturedBody['ClientId'], '4p3oehrll2pd9p1ann0gvubp1c');
        expect(capturedBody['AuthParameters']['USERNAME'], 'ARCH-9942');
        expect(capturedBody['AuthParameters']['PASSWORD'], 'Passkey_1234!@#');

        expect(session.accessToken, 'cognito_access_jwt_valid');
        expect(session.refreshToken, 'cognito_refresh_jwt_valid');
        expect(session.researcherName, 'Dr. Nithish R.');
        expect(session.clearanceLevel, 'Level-3 Architect');
        expect(session.email, 'nithish@synqra.ai');
        expect(session.isExpired, isFalse);

        // Verify session persists in secure storage fallback
        final saved = await repo.loadSavedSession();
        expect(saved, isNotNull);
        expect(saved!.accessToken, 'cognito_access_jwt_valid');
      },
    );

    test('Managed Login PKCE exchanges code and creates session', () async {
      final header = base64Url.encode(
        utf8.encode(jsonEncode({'alg': 'RS256'})),
      );
      final payload = base64Url.encode(
        utf8.encode(
          jsonEncode({
            'sub': 'managed-uuid-5555',
            'cognito:username': 'ARCH-COGNITO-USER',
            'email': 'operator@synqra.ai',
          }),
        ),
      );
      final dummyIdToken = '$header.$payload.signature';

      final fakeAppAuth = FakeFlutterAppAuth(
        mockAuthResponse: AuthorizationTokenResponse(
          'managed_access_token_pkce',
          'managed_refresh_token_pkce',
          DateTime.now().add(const Duration(hours: 1)),
          dummyIdToken,
          'Bearer',
          const ['openid', 'email'],
          null,
          null,
        ),
      );

      final memoryStorage = <String, String>{};
      final repo = CognitoAuthRepository(
        appAuth: fakeAppAuth,
        memoryStorageFallback: memoryStorage,
      );

      final session = await repo.signInWithManagedLogin(config: testConfig);

      expect(session.accessToken, 'managed_access_token_pkce');
      expect(session.refreshToken, 'managed_refresh_token_pkce');
      expect(session.username, 'ARCH-COGNITO-USER');
      expect(session.email, 'operator@synqra.ai');

      // Verify sign out ends session in AppAuth and clears storage
      await repo.signOutWithManagedLogin(
        idToken: session.idToken,
        config: testConfig,
      );
      expect(fakeAppAuth.endSessionCalled, isTrue);
      final emptySession = await repo.loadSavedSession();
      expect(emptySession, isNull);
    });

    test(
      'Throws CognitoAuthException with code when Cognito returns error',
      () async {
        final mockClient = MockClient((request) async {
          return http.Response(
            jsonEncode({
              '__type': 'NotAuthorizedException',
              'message': 'Incorrect username or password.',
            }),
            400,
            headers: {'content-type': 'application/x-amz-json-1.1'},
          );
        });

        final repo = CognitoAuthRepository(client: mockClient);

        expect(
          () => repo.signIn(
            username: 'ARCH-9942',
            password: 'wrong_password',
            config: testConfig,
          ),
          throwsA(
            predicate<CognitoAuthException>(
              (e) =>
                  e.code == 'NotAuthorizedException' &&
                  e.message.contains('Incorrect username or password'),
            ),
          ),
        );
      },
    );

    test(
      'SignUp dispatches user attributes and returns confirmation state',
      () async {
        late Map<String, dynamic> capturedBody;

        final mockClient = MockClient((request) async {
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({'UserConfirmed': false, 'UserSub': 'sub-9988-7766'}),
            200,
            headers: {'content-type': 'application/x-amz-json-1.1'},
          );
        });

        final repo = CognitoAuthRepository(client: mockClient);
        final isConfirmed = await repo.signUp(
          username: 'ARCH-9942',
          password: 'SecurePass_123!',
          email: 'researcher@synqra.ai',
          researcherName: 'Dr. Nithish R.',
          clearanceLevel: 'Level-3 Architect',
          config: testConfig,
        );

        expect(isConfirmed, isFalse);
        expect(capturedBody['ClientId'], '4p3oehrll2pd9p1ann0gvubp1c');
        expect(capturedBody['Username'], 'ARCH-9942');
        final attrs = capturedBody['UserAttributes'] as List;
        expect(
          attrs.any(
            (a) => a['Name'] == 'email' && a['Value'] == 'researcher@synqra.ai',
          ),
          isTrue,
        );
      },
    );
  });

  group('SettingsProvider with Cognito Integration Tests', () {
    test(
      'signIn stores Cognito access token in settings.apiKey and sets isAuthenticated',
      () async {
        final mockCognito = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'AuthenticationResult': {
                'AccessToken': 'cognito_jwt_for_backend_requests',
                'RefreshToken': 'refresh_xyz',
                'ExpiresIn': 3600,
              },
            }),
            200,
            headers: {'content-type': 'application/x-amz-json-1.1'},
          );
        });

        final memoryStorage = <String, String>{};
        final cognitoRepo = CognitoAuthRepository(
          client: mockCognito,
          memoryStorageFallback: memoryStorage,
        );
        await cognitoRepo.saveConfig(testConfig);

        final settingsRepo = ProfileSettingsRepository();
        final provider = SettingsProvider(
          repository: settingsRepo,
          cognitoRepository: cognitoRepo,
        );
        await provider.updateCognitoConfig(testConfig);

        final success = await provider.signIn(
          callSign: 'ARCH-9942',
          passkey: 'SecretPass_123!',
        );

        expect(success, isTrue);
        expect(provider.isAuthenticated, isTrue);
        expect(provider.settings.apiKey, 'cognito_jwt_for_backend_requests');
        expect(provider.cognitoSession, isNotNull);
        expect(
          provider.cognitoSession!.accessToken,
          'cognito_jwt_for_backend_requests',
        );

        // Verify signOut clears token
        await provider.signOut();
        expect(provider.isAuthenticated, isFalse);
        expect(provider.settings.apiKey, '');
        expect(provider.cognitoSession, isNull);
      },
    );

    test('signInWithManagedLogin sets isAuthenticated and apiKey', () async {
      final fakeAppAuth = FakeFlutterAppAuth(
        mockAuthResponse: AuthorizationTokenResponse(
          'cognito_managed_access_token',
          'refresh_token',
          DateTime.now().add(const Duration(hours: 1)),
          null,
          'Bearer',
          const ['openid', 'email'],
          null,
          null,
        ),
      );

      final memoryStorage = <String, String>{};
      final cognitoRepo = CognitoAuthRepository(
        appAuth: fakeAppAuth,
        memoryStorageFallback: memoryStorage,
      );
      final settingsRepo = ProfileSettingsRepository();
      final provider = SettingsProvider(
        repository: settingsRepo,
        cognitoRepository: cognitoRepo,
      );
      await provider.updateCognitoConfig(testConfig);

      final success = await provider.signInWithManagedLogin();

      expect(success, isTrue);
      expect(provider.isAuthenticated, isTrue);
      expect(provider.settings.apiKey, 'cognito_managed_access_token');
    });

    test('getValidAccessToken automatically rotates expired session', () async {
      final fakeAppAuth = FakeFlutterAppAuth(
        mockTokenResponse: TokenResponse(
          'refreshed_access_token_rotated',
          'new_refresh_token',
          DateTime.now().add(const Duration(hours: 1)),
          null,
          'Bearer',
          const ['openid', 'email'],
          null,
        ),
      );

      final memoryStorage = <String, String>{};
      final cognitoRepo = CognitoAuthRepository(
        appAuth: fakeAppAuth,
        memoryStorageFallback: memoryStorage,
      );
      final expiredSession = CognitoAuthSession(
        accessToken: 'stale_token',
        refreshToken: 'valid_refresh',
        expiresAt: DateTime.now().subtract(const Duration(minutes: 5)),
        username: 'ARCH-OPERATOR',
      );
      await cognitoRepo.saveSession(expiredSession);

      final settingsRepo = ProfileSettingsRepository();
      final provider = SettingsProvider(
        repository: settingsRepo,
        cognitoRepository: cognitoRepo,
      );
      await provider.updateCognitoConfig(testConfig);

      final token = await provider.getValidAccessToken();
      expect(token, 'refreshed_access_token_rotated');
      expect(provider.settings.apiKey, 'refreshed_access_token_rotated');
    });
  });

  group('AuthenticatedHttpClient Tests', () {
    test(
      'attaches Authorization Bearer header when token is present',
      () async {
        late http.Request captured;
        final mockInner = MockClient((request) async {
          captured = request;
          return http.Response('{"status":"ok"}', 200);
        });

        final client = AuthenticatedHttpClient(
          client: mockInner,
          getAccessToken: () async => 'cognito_active_bearer_token',
        );

        final response = await client.get(
          Uri.parse('https://api.synqra.ai/questions'),
        );
        expect(response.statusCode, 200);
        expect(
          captured.headers['Authorization'],
          'Bearer cognito_active_bearer_token',
        );
      },
    );

    test('suppresses masked ****** from Authorization header', () async {
      late http.Request captured;
      final mockInner = MockClient((request) async {
        captured = request;
        return http.Response('{"status":"ok"}', 200);
      });

      final client = AuthenticatedHttpClient(
        client: mockInner,
        getAccessToken: () async => '******',
      );

      await client.get(Uri.parse('https://api.synqra.ai/questions'));
      expect(captured.headers.containsKey('Authorization'), isFalse);
    });

    test(
      'does not transmit real bearer token over cleartext http (HTTPS required)',
      () async {
        late http.Request captured;
        final mockInner = MockClient((request) async {
          captured = request;
          return http.Response('{"status":"ok"}', 200);
        });

        final client = AuthenticatedHttpClient(
          client: mockInner,
          getAccessToken: () async => 'cognito_bearer_token',
        );

        // Target cleartext http backend
        final response = await client.get(
          Uri.parse('http://32.236.134.203/questions'),
        );
        expect(response.statusCode, 200);
        expect(captured.headers.containsKey('Authorization'), isFalse);
      },
    );

    test(
      'resetPassword and confirmResetPassword trigger Cognito API',
      () async {
        late String capturedAction;
        late Map<String, dynamic> capturedBody;

        final mockClient = MockClient((request) async {
          capturedAction = request.headers['X-Amz-Target']!;
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{}', 200);
        });

        final cognitoRepo = CognitoAuthRepository(
          client: mockClient,
          memoryStorageFallback: {},
        );

        await cognitoRepo.resetPassword(
          username: 'ARCH-9942',
          config: testConfig,
        );
        expect(
          capturedAction,
          'AWSCognitoIdentityProviderService.ForgotPassword',
        );
        expect(capturedBody['Username'], 'ARCH-9942');
        expect(capturedBody['ClientId'], testConfig.appClientId);

        await cognitoRepo.confirmResetPassword(
          username: 'ARCH-9942',
          newPassword: 'NewCryptographicPasskey!123',
          confirmationCode: '654321',
          config: testConfig,
        );
        expect(
          capturedAction,
          'AWSCognitoIdentityProviderService.ConfirmForgotPassword',
        );
        expect(capturedBody['Username'], 'ARCH-9942');
        expect(capturedBody['Password'], 'NewCryptographicPasskey!123');
        expect(capturedBody['ConfirmationCode'], '654321');
      },
    );
  });
}
