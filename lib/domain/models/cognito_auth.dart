import 'dart:convert';

class CognitoConfig {
  final String region;
  final String userPoolId;
  final String appClientId;
  final String cognitoDomain;
  final String callbackUri;
  final List<String> scopes;
  final bool isEnabled;

  const CognitoConfig({
    required this.region,
    required this.userPoolId,
    required this.appClientId,
    required this.cognitoDomain,
    required this.callbackUri,
    this.scopes = const ['openid', 'email'],
    this.isEnabled = true,
  });

  factory CognitoConfig.defaults() {
    return const CognitoConfig(
      region: 'ap-southeast-2',
      userPoolId: 'ap-southeast-2_cR0iLu56D',
      appClientId: '4p3oehrll2pd9p1ann0gvubp1c',
      cognitoDomain:
          'https://ap-southeast-2cr0ilu56d.auth.ap-southeast-2.amazoncognito.com',
      callbackUri: 'com.example.synqra://auth/callback',
      scopes: ['openid', 'email'],
      isEnabled: true,
    );
  }

  String get endpoint => 'https://cognito-idp.$region.amazonaws.com/';

  String get issuer => 'https://cognito-idp.$region.amazonaws.com/$userPoolId';

  String get discoveryUrl =>
      'https://cognito-idp.$region.amazonaws.com/$userPoolId/.well-known/openid-configuration';

  String get cleanDomain => cognitoDomain.trim().replaceAll(RegExp(r'/+$'), '');

  String get authorizationEndpoint => '$cleanDomain/oauth2/authorize';

  String get tokenEndpoint => '$cleanDomain/oauth2/token';

  String get endSessionEndpoint => '$cleanDomain/logout';

  bool get isConfigured =>
      userPoolId.trim().isNotEmpty && appClientId.trim().isNotEmpty;

  CognitoConfig copyWith({
    String? region,
    String? userPoolId,
    String? appClientId,
    String? cognitoDomain,
    String? callbackUri,
    List<String>? scopes,
    bool? isEnabled,
  }) {
    return CognitoConfig(
      region: region ?? this.region,
      userPoolId: userPoolId ?? this.userPoolId,
      appClientId: appClientId ?? this.appClientId,
      cognitoDomain: cognitoDomain ?? this.cognitoDomain,
      callbackUri: callbackUri ?? this.callbackUri,
      scopes: scopes ?? this.scopes,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'region': region,
    'userPoolId': userPoolId,
    'appClientId': appClientId,
    'cognitoDomain': cognitoDomain,
    'callbackUri': callbackUri,
    'scopes': scopes,
    'isEnabled': isEnabled,
  };

  factory CognitoConfig.fromJson(Map<String, dynamic> json) {
    return CognitoConfig(
      region: json['region']?.toString() ?? 'ap-southeast-2',
      userPoolId: json['userPoolId']?.toString() ?? 'ap-southeast-2_cR0iLu56D',
      appClientId:
          json['appClientId']?.toString() ?? '4p3oehrll2pd9p1ann0gvubp1c',
      cognitoDomain:
          json['cognitoDomain']?.toString() ??
          'https://ap-southeast-2cr0ilu56d.auth.ap-southeast-2.amazoncognito.com',
      callbackUri:
          json['callbackUri']?.toString() ??
          'com.example.synqra://auth/callback',
      scopes:
          json['scopes'] is List
              ? (json['scopes'] as List).map((e) => e.toString()).toList()
              : const ['openid', 'email'],
      isEnabled: json['isEnabled'] != false,
    );
  }
}

class CognitoAuthSession {
  final String accessToken;
  final String? idToken;
  final String? refreshToken;
  final DateTime expiresAt;
  final String username;
  final String? researcherName;
  final String? clearanceLevel;
  final String? email;

  const CognitoAuthSession({
    required this.accessToken,
    this.idToken,
    this.refreshToken,
    required this.expiresAt,
    required this.username,
    this.researcherName,
    this.clearanceLevel,
    this.email,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'idToken': idToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt.toIso8601String(),
    'username': username,
    'researcherName': researcherName,
    'clearanceLevel': clearanceLevel,
    'email': email,
  };

  factory CognitoAuthSession.fromJson(Map<String, dynamic> json) {
    return CognitoAuthSession(
      accessToken: json['accessToken']?.toString() ?? '',
      idToken: json['idToken']?.toString(),
      refreshToken: json['refreshToken']?.toString(),
      expiresAt:
          DateTime.tryParse(json['expiresAt']?.toString() ?? '') ??
          DateTime.now().add(const Duration(hours: 1)),
      username: json['username']?.toString() ?? '',
      researcherName: json['researcherName']?.toString(),
      clearanceLevel: json['clearanceLevel']?.toString(),
      email: json['email']?.toString(),
    );
  }

  static Map<String, dynamic> decodeJwtPayload(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return {};
      final normalized = base64Url.normalize(parts[1]);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final json = jsonDecode(decoded);
      if (json is Map<String, dynamic>) return json;
      return {};
    } catch (_) {
      return {};
    }
  }
}
