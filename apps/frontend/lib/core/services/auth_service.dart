import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class AuthService {
  final _storage = const FlutterSecureStorage();
  final String _clientId = 'easychat-flutter-client';
  final String _keycloakBaseUrl = 'https://keycloak.easychat.local/realms/easychat';

  // Generate cryptographically secure PKCE code verifier
  String _generateCodeVerifier() {
    final random = Random.secure();
    final values = List<int>.generate(32, (i) => random.nextInt(256));
    return base64UrlEncode(values).replaceAll('=', '');
  }

  // Derive PKCE code challenge from verifier using SHA-256
  String _deriveCodeChallenge(String verifier) {
    final bytes = utf8.encode(verifier);
    final digest = sha256.convert(bytes);
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  // Build Authorization URI
  Future<String> getAuthorizationUrl() async {
    final verifier = _generateCodeVerifier();
    final challenge = _deriveCodeChallenge(verifier);

    // Persist verifier securely to match against code exchange later
    await _storage.write(key: 'pkce_code_verifier', value: verifier);

    final redirectUri = Uri.encodeComponent('easychat://oauth2/callback');
    return '$_keycloakBaseUrl/protocol/openid-connect/auth'
        '?response_type=code'
        '&client_id=$_clientId'
        '&redirect_uri=$redirectUri'
        '&code_challenge=$challenge'
        '&code_challenge_method=S256'
        '&scope=openid%20profile%20email';
  }

  // Exchange Auth Code for OIDC tokens
  Future<bool> handleAuthorizationCallback(String authCode) async {
    final verifier = await _storage.read(key: 'pkce_code_verifier');
    if (verifier == null) return false;

    const redirectUri = 'easychat://oauth2/callback';
    final tokenUrl = Uri.parse('$_keycloakBaseUrl/protocol/openid-connect/token');

    final response = await http.post(
      tokenUrl,
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'authorization_code',
        'client_id': _clientId,
        'code': authCode,
        'redirect_uri': redirectUri,
        'code_verifier': verifier,
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      await _storage.write(key: 'access_token', value: data['access_token']);
      await _storage.write(key: 'refresh_token', value: data['refresh_token']);
      await _storage.write(key: 'id_token', value: data['id_token']);
      await _storage.delete(key: 'pkce_code_verifier');
      return true;
    }
    return false;
  }

  // Dynamic Token Refresh Flow
  Future<bool> refreshAccessToken() async {
    final refreshToken = await _storage.read(key: 'refresh_token');
    if (refreshToken == null) return false;

    final tokenUrl = Uri.parse('$_keycloakBaseUrl/protocol/openid-connect/token');
    final response = await http.post(
      tokenUrl,
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'refresh_token',
        'client_id': _clientId,
        'refresh_token': refreshToken,
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      await _storage.write(key: 'access_token', value: data['access_token']);
      if (data['refresh_token'] != null) {
        await _storage.write(key: 'refresh_token', value: data['refresh_token']);
      }
      return true;
    }
    return false;
  }

  // Session Logout
  Future<void> logout() async {
    final refreshToken = await _storage.read(key: 'refresh_token');
    if (refreshToken != null) {
      final logoutUrl = Uri.parse('$_keycloakBaseUrl/protocol/openid-connect/logout');
      await http.post(
        logoutUrl,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': _clientId,
          'refresh_token': refreshToken,
        },
      );
    }
    await _storage.deleteAll();
  }

  // Validate Access Token expiration status
  Future<bool> isSessionValid() async {
    final accessToken = await _storage.read(key: 'access_token');
    if (accessToken == null) return false;

    try {
      final parts = accessToken.split('.');
      if (parts.length != 3) return false;

      // Pad payload string to base64 compliance
      var normalizedPayload = base64.normalize(parts[1]);
      final payloadBytes = base64Url.decode(normalizedPayload);
      final claims = json.decode(utf8.decode(payloadBytes));

      final exp = claims['exp'] as int;
      final now = DateTime.now().millisecondsSinceEpoch / 1000;
      
      // Token is valid if expiration exceeds now with a 10s buffer
      if (exp > now + 10) return true;

      // Expiry failed, attempt token refresh before dropping session
      return await refreshAccessToken();
    } catch (_) {
      return false;
    }
  }

  Future<String?> getAccessToken() async {
    if (await isSessionValid()) {
      return await _storage.read(key: 'access_token');
    }
    return null;
  }
}

// Extension to safely normalize base64 strings
extension Base64Padding on Base64Codec {
  String normalize(String base64str) {
    var str = base64str;
    while (str.length % 4 != 0) {
      str += '=';
    }
    return str;
  }
}
