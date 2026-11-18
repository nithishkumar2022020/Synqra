import 'package:http/http.dart' as http;

/// An HTTP client wrapper that dynamically resolves and attaches the active
/// AWS Cognito Bearer Access Token to outgoing requests destined for the
/// FastAPI backend on EC2.
class AuthenticatedHttpClient extends http.BaseClient {
  final http.Client _inner;
  final Future<String?> Function() _getAccessToken;

  AuthenticatedHttpClient({
    http.Client? client,
    required Future<String?> Function() getAccessToken,
  }) : _inner = client ?? http.Client(),
       _getAccessToken = getAccessToken;

  static bool _isValidBearerToken(String? token) {
    if (token == null) return false;
    final trimmed = token.trim();
    if (trimmed.isEmpty) return false;
    // Suppress masked password/asterisk tokens
    if (RegExp(r'^[\*•\s]+$').hasMatch(trimmed)) return false;
    return true;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    try {
      // Security constraint: Do not transmit real access tokens to an HTTP-only backend.
      // Authenticated requests require an encrypted HTTPS transport.
      if (request.url.scheme == 'https') {
        final token = await _getAccessToken();
        if (_isValidBearerToken(token) &&
            !request.headers.containsKey('Authorization')) {
          request.headers['Authorization'] = 'Bearer ${token!.trim()}';
        }
      }
    } catch (_) {
      // In case token retrieval fails, proceed with the original request
    }

    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
