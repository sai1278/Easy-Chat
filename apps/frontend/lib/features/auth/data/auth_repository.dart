import 'dart:convert';
import 'dart:developer' as dev;
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/network/environment.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    dioClient: DioClient(),
    secureStorage: const FlutterSecureStorage(),
  );
});

final authStateProvider = FutureProvider<bool>((ref) async {
  final authRepo = ref.watch(authRepositoryProvider);
  return await authRepo.restoreSession();
});

class AuthRepository {
  final DioClient _dioClient;
  final FlutterSecureStorage _secureStorage;

  static const _tokenKey = 'jwt_access_token';
  static const _refreshTokenKey = 'jwt_refresh_token';
  static const _deviceIdKey = 'device_hardware_id';
  static const _userIdKey = 'authenticated_user_id';
  static const _loginTimestampKey = 'authenticated_login_timestamp';

  AuthRepository({
    required DioClient dioClient,
    required FlutterSecureStorage secureStorage,
  })  : _dioClient = dioClient,
        _secureStorage = secureStorage;

  Future<String> getDeviceId() async {
    var id = await _secureStorage.read(key: _deviceIdKey);
    if (id == null || id.isEmpty) {
      id = 'dev_${const Uuid().v4()}';
      await _secureStorage.write(key: _deviceIdKey, value: id);
      dev.log('[AUTH_DEBUG] Generated new Device Hardware ID: $id', name: 'Auth');
    }
    return id;
  }

  Future<String?> getAccessToken() async {
    return await _secureStorage.read(key: _tokenKey);
  }

  Future<String?> getUserId() async {
    return await _secureStorage.read(key: _userIdKey);
  }

  Future<bool> restoreSession() async {
    final token = await getAccessToken();
    if (token != null && token.isNotEmpty) {
      await _dioClient.updateToken(token);
      dev.log('[AUTH_DEBUG] Session restored with token.', name: 'Auth');
      return true;
    }
    dev.log('[AUTH_DEBUG] No active session.', name: 'Auth');
    return false;
  }

  Future<bool> isAuthenticated() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }

  Future<void> registerAndLogin(String password) async {
    final deviceId = await getDeviceId();
    dev.log('[AUTH_DEBUG] Stage 1: registerAndLogin called with deviceId: $deviceId', name: 'Auth');

    try {
      final url = '${_dioClient.dio.options.baseUrl}/auth/register';
      dev.log('[AUTH_DEBUG] Stage 2: Sending POST to URL: $url', name: 'Auth');
      final response = await _dioClient.dio.post(
        '/auth/register',
        data: {
          'device_id': deviceId,
          'password': password,
        },
      );
      dev.log('[AUTH_DEBUG] Stage 3: Register Response status: ${response.statusCode}, data: ${response.data}', name: 'Auth');
      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final userId = data['id'] as String? ?? '';
        if (userId.isNotEmpty) {
          await _secureStorage.write(key: _userIdKey, value: userId);
        }
      }
    } on DioException catch (e) {
      dev.log('[AUTH_DEBUG] Stage 3 (DioException): type=${e.type}, msg=${e.message}, err=${e.error}, status=${e.response?.statusCode}, data=${e.response?.data}', name: 'Auth');
      if (e.response?.statusCode == 409) {
        dev.log('[AUTH_DEBUG] Stage 3: HTTP 409 Conflict (Device already registered). Fallback to login.', name: 'Auth');
      } else {
        throw _parseDioException(e);
      }
    } catch (e, stack) {
      dev.log('[AUTH_DEBUG] Stage 3 (Catch All Exception): $e\nStack: $stack', name: 'Auth');
      throw Exception('Registration error: $e');
    }

    dev.log('[AUTH_DEBUG] Stage 4: Proceeding to login($password)', name: 'Auth');
    await login(password);
  }

  Future<String> login(String password) async {
    final deviceId = await getDeviceId();
    dev.log('[AUTH_DEBUG] Stage 5: login called for deviceId: $deviceId', name: 'Auth');
    try {
      final url = '${_dioClient.dio.options.baseUrl}/auth/login';
      dev.log('[AUTH_DEBUG] Stage 6: Sending POST to URL: $url', name: 'Auth');
      final response = await _dioClient.dio.post(
        '/auth/login',
        data: {
          'device_id': deviceId,
          'password': password,
        },
      );
      dev.log('[AUTH_DEBUG] Stage 7: Login Response status: ${response.statusCode}, data: ${response.data}', name: 'Auth');
      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final accessToken = data['access_token'] as String;
        final refreshToken = data['refresh_token'] as String?;

        await _secureStorage.write(key: _tokenKey, value: accessToken);
        if (refreshToken != null) {
          await _secureStorage.write(key: _refreshTokenKey, value: refreshToken);
        }
        try {
          final parts = accessToken.split('.');
          if (parts.length == 3) {
            final normalized = base64Url.normalize(parts[1]);
            final payloadMap = jsonDecode(utf8.decode(base64Url.decode(normalized))) as Map<String, dynamic>;
            final sub = payloadMap['sub'] as String?;
            if (sub != null && sub.isNotEmpty) {
              await _secureStorage.write(key: _userIdKey, value: sub);
            }
          }
        } catch (_) {}

        final nowIso = DateTime.now().toUtc().toIso8601String();
        await _secureStorage.write(key: _loginTimestampKey, value: nowIso);

        dev.log('[AUTH_DEBUG] Stage 8: Tokens & Timestamp ($nowIso) stored in FlutterSecureStorage.', name: 'Auth');

        await _dioClient.updateToken(accessToken);
        return accessToken;
      }
      throw Exception('Login failed with status ${response.statusCode}');
    } on DioException catch (e) {
      dev.log('[AUTH_DEBUG] Stage 7 (DioException): type=${e.type}, msg=${e.message}, err=${e.error}, status=${e.response?.statusCode}, data=${e.response?.data}', name: 'Auth');
      throw _parseDioException(e);
    } catch (e, stack) {
      dev.log('[AUTH_DEBUG] Stage 7 (Catch All Exception): $e\nStack: $stack', name: 'Auth');
      rethrow;
    }
  }

  Exception _parseDioException(DioException e) {
    dev.log('[AUTH_DEBUG] _parseDioException: type=${e.type}, message=${e.message}, responseStatus=${e.response?.statusCode}, responseData=${e.response?.data}', name: 'Auth');
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return Exception('Connection timeout. Please check your connection to the API Gateway.');
    }
    if (e.type == DioExceptionType.connectionError) {
      final cfg = ApiConfig.fromEnvironment();
      return Exception(
        'Current Environment : ${cfg.environment.name.toUpperCase()}\n'
        'Target API : ${cfg.baseUrl}\n'
        'Connection Failed\n'
        'Reason : Connection Refused\n\n'
        'Suggested Actions:\n'
        '• Verify backend containers are running (`docker ps`)\n'
        '• Verify Gateway is listening on port ${cfg.gatewayPort}\n'
        '• Verify Wi-Fi network connectivity (${cfg.host})\n'
        '• Verify host IP and port settings in --dart-define'
      );
    }
    if (e.response != null) {
      final status = e.response!.statusCode;
      String? serverMsg;
      if (e.response!.data is Map) {
        serverMsg = (e.response!.data as Map)['error'] ?? (e.response!.data as Map)['message'];
      } else if (e.response!.data is String) {
        serverMsg = e.response!.data as String;
      }
      if (status == 401) {
        return Exception(serverMsg ?? 'Invalid credentials provided.');
      }
      if (status == 409) {
        return Exception(serverMsg ?? 'Device already registered.');
      }
      if (status == 429) {
        return Exception(serverMsg ?? 'Too many requests. Please wait a moment and try again.');
      }
      if (status == 500) {
        return Exception(serverMsg ?? 'Backend internal server error.');
      }
      return Exception(serverMsg ?? 'HTTP Error $status');
    }
    return Exception(e.message ?? (e.error != null ? e.error.toString() : 'Unknown network error.'));
  }

  Future<void> logout() async {
    dev.log('[AUTH_DEBUG] Logging out & clearing secure storage.', name: 'Auth');
    await _secureStorage.delete(key: _tokenKey);
    await _secureStorage.delete(key: _refreshTokenKey);
    await _secureStorage.delete(key: _userIdKey);
    await _secureStorage.delete(key: _loginTimestampKey);
    await _dioClient.updateToken(null);
  }
}
