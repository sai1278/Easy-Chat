import 'dart:convert';
import 'dart:developer' as dev;
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/network/environment.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final dioClient = ref.watch(dioClientProvider);
  return AuthRepository(
    dioClient: dioClient,
    secureStorage: const FlutterSecureStorage(),
  );
});

final authStateProvider = FutureProvider<bool>((ref) async {
  dev.log('[RIVERPOD][STEP-01] Before authStateProvider restoreSession()', name: 'AuthTrace');
  final authRepo = ref.watch(authRepositoryProvider);
  final sw = Stopwatch()..start();
  final result = await authRepo.restoreSession();
  sw.stop();
  dev.log('[RIVERPOD][STEP-02] After authStateProvider restoreSession() - Duration: ${sw.elapsedMilliseconds} ms - Result: $result', name: 'AuthTrace');
  return result;
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
    final sw = Stopwatch()..start();
    dev.log('[AUTH][STEP-01] Before SecureStorage.read(_deviceIdKey)', name: 'AuthTrace');
    var id = await _secureStorage.read(key: _deviceIdKey);
    sw.stop();
    dev.log('[AUTH][STEP-01] After SecureStorage.read(_deviceIdKey) - Duration: ${sw.elapsedMilliseconds} ms - Value: $id', name: 'AuthTrace');

    if (id == null || id.isEmpty) {
      id = 'dev_${const Uuid().v4()}';
      final sw2 = Stopwatch()..start();
      dev.log('[AUTH][STEP-02] Before SecureStorage.write(_deviceIdKey)', name: 'AuthTrace');
      await _secureStorage.write(key: _deviceIdKey, value: id);
      sw2.stop();
      dev.log('[AUTH][STEP-02] After SecureStorage.write(_deviceIdKey) - Duration: ${sw2.elapsedMilliseconds} ms - Value: $id', name: 'AuthTrace');
    }
    return id;
  }

  Future<String?> getAccessToken() async {
    final sw = Stopwatch()..start();
    dev.log('[AUTH][STEP-03] Before SecureStorage.read(_tokenKey)', name: 'AuthTrace');
    final token = await _secureStorage.read(key: _tokenKey);
    sw.stop();
    dev.log('[AUTH][STEP-03] After SecureStorage.read(_tokenKey) - Duration: ${sw.elapsedMilliseconds} ms', name: 'AuthTrace');
    return token;
  }

  Future<String?> getUserId() async {
    final sw = Stopwatch()..start();
    dev.log('[AUTH][STEP-04] Before SecureStorage.read(_userIdKey)', name: 'AuthTrace');
    final uid = await _secureStorage.read(key: _userIdKey);
    sw.stop();
    dev.log('[AUTH][STEP-04] After SecureStorage.read(_userIdKey) - Duration: ${sw.elapsedMilliseconds} ms', name: 'AuthTrace');
    return uid;
  }

  Future<bool> restoreSession() async {
    dev.log('[AUTH][STEP-05] Before restoreSession getAccessToken()', name: 'AuthTrace');
    final token = await getAccessToken();
    if (token != null && token.isNotEmpty) {
      final sw = Stopwatch()..start();
      dev.log('[AUTH][STEP-06] Before updateToken(token)', name: 'AuthTrace');
      await _dioClient.updateToken(token);
      sw.stop();
      dev.log('[AUTH][STEP-06] After updateToken(token) - Duration: ${sw.elapsedMilliseconds} ms', name: 'AuthTrace');
      return true;
    }
    dev.log('[AUTH][STEP-07] restoreSession completed: No active session.', name: 'AuthTrace');
    return false;
  }

  Future<bool> isAuthenticated() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }

  Future<void> registerAndLogin(String password, {String? displayName}) async {
    dev.log('[AUTH][STEP-08] Before registerAndLogin getDeviceId()', name: 'AuthTrace');
    final deviceId = await getDeviceId();
    dev.log('[AUTH][STEP-08] After registerAndLogin getDeviceId() - deviceId: $deviceId', name: 'AuthTrace');

    try {
      final url = '${_dioClient.dio.options.baseUrl}/auth/register';
      dev.log('[AUTH][STEP-09] Before Dio POST /auth/register - Target URL: $url', name: 'AuthTrace');
      final sw = Stopwatch()..start();
      final regData = <String, dynamic>{
        'device_id': deviceId,
        'password': password,
      };
      if (displayName != null && displayName.isNotEmpty) {
        regData['display_name'] = displayName;
        regData['username'] = displayName;
      }
      final response = await _dioClient.dio.post(
        '/auth/register',
        data: regData,
      );
      sw.stop();
      dev.log('[AUTH][STEP-09] After Dio POST /auth/register - Duration: ${sw.elapsedMilliseconds} ms - Status: ${response.statusCode}', name: 'AuthTrace');

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final userId = data['id'] as String? ?? '';
        if (userId.isNotEmpty) {
          final swW = Stopwatch()..start();
          dev.log('[AUTH][STEP-10] Before SecureStorage.write(_userIdKey)', name: 'AuthTrace');
          await _secureStorage.write(key: _userIdKey, value: userId);
          swW.stop();
          dev.log('[AUTH][STEP-10] After SecureStorage.write(_userIdKey) - Duration: ${swW.elapsedMilliseconds} ms', name: 'AuthTrace');
        }
      }
    } on DioException catch (e) {
      dev.log('[AUTH][STEP-09-ERR] DioException during register: type=${e.type}, status=${e.response?.statusCode}', name: 'AuthTrace');
      if (e.response?.statusCode == 409) {
        dev.log('[AUTH][STEP-09-CONFLICT] HTTP 409 Conflict. Device registered. Proceeding to login.', name: 'AuthTrace');
      } else {
        throw _parseDioException(e);
      }
    } catch (e, stack) {
      dev.log('[AUTH][STEP-09-EXC] Catch-all Exception during register: $e\n$stack', name: 'AuthTrace');
      throw Exception('Registration error: $e');
    }

    dev.log('[AUTH][STEP-11] Before proceeding to login()', name: 'AuthTrace');
    await login(password);
    dev.log('[AUTH][STEP-12] After login() completed', name: 'AuthTrace');

    if (displayName != null && displayName.isNotEmpty) {
      try {
        await _dioClient.dio.put(
          '/user/profile',
          data: {
            'display_name': displayName,
            'username': displayName,
            'avatar_url': '',
            'bio': 'Proximity Chat User',
          },
        );
      } catch (e) {
        dev.log('[AUTH] Syncing initial profile failed (non-fatal): $e', name: 'AuthTrace');
      }
    }
  }

  Future<String> login(String password) async {
    dev.log('[AUTH][STEP-13] Before login getDeviceId()', name: 'AuthTrace');
    final deviceId = await getDeviceId();
    dev.log('[AUTH][STEP-13] After login getDeviceId() - deviceId: $deviceId', name: 'AuthTrace');

    try {
      final url = '${_dioClient.dio.options.baseUrl}/auth/login';
      dev.log('[AUTH][STEP-14] Before Dio POST /auth/login - Target URL: $url', name: 'AuthTrace');
      final sw = Stopwatch()..start();
      final response = await _dioClient.dio.post(
        '/auth/login',
        data: {
          'device_id': deviceId,
          'password': password,
        },
      );
      sw.stop();
      dev.log('[AUTH][STEP-14] After Dio POST /auth/login - Duration: ${sw.elapsedMilliseconds} ms - Status: ${response.statusCode}', name: 'AuthTrace');

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final accessToken = data['access_token'] as String;
        final refreshToken = data['refresh_token'] as String?;

        final swT = Stopwatch()..start();
        dev.log('[AUTH][STEP-15] Before SecureStorage.write(_tokenKey)', name: 'AuthTrace');
        await _secureStorage.write(key: _tokenKey, value: accessToken);
        swT.stop();
        dev.log('[AUTH][STEP-15] After SecureStorage.write(_tokenKey) - Duration: ${swT.elapsedMilliseconds} ms', name: 'AuthTrace');

        if (refreshToken != null) {
          final swR = Stopwatch()..start();
          dev.log('[AUTH][STEP-16] Before SecureStorage.write(_refreshTokenKey)', name: 'AuthTrace');
          await _secureStorage.write(key: _refreshTokenKey, value: refreshToken);
          swR.stop();
          dev.log('[AUTH][STEP-16] After SecureStorage.write(_refreshTokenKey) - Duration: ${swR.elapsedMilliseconds} ms', name: 'AuthTrace');
        }

        try {
          final parts = accessToken.split('.');
          if (parts.length == 3) {
            final normalized = base64Url.normalize(parts[1]);
            final payloadMap = jsonDecode(utf8.decode(base64Url.decode(normalized))) as Map<String, dynamic>;
            final sub = payloadMap['sub'] as String?;
            if (sub != null && sub.isNotEmpty) {
              final swSub = Stopwatch()..start();
              dev.log('[AUTH][STEP-17] Before SecureStorage.write(_userIdKey sub)', name: 'AuthTrace');
              await _secureStorage.write(key: _userIdKey, value: sub);
              swSub.stop();
              dev.log('[AUTH][STEP-17] After SecureStorage.write(_userIdKey sub) - Duration: ${swSub.elapsedMilliseconds} ms', name: 'AuthTrace');
            }
          }
        } catch (_) {}

        final nowIso = DateTime.now().toUtc().toIso8601String();
        final swTS = Stopwatch()..start();
        dev.log('[AUTH][STEP-18] Before SecureStorage.write(_loginTimestampKey)', name: 'AuthTrace');
        await _secureStorage.write(key: _loginTimestampKey, value: nowIso);
        swTS.stop();
        dev.log('[AUTH][STEP-18] After SecureStorage.write(_loginTimestampKey) - Duration: ${swTS.elapsedMilliseconds} ms', name: 'AuthTrace');

        final swUp = Stopwatch()..start();
        dev.log('[AUTH][STEP-19] Before dioClient.updateToken()', name: 'AuthTrace');
        await _dioClient.updateToken(accessToken);
        swUp.stop();
        dev.log('[AUTH][STEP-19] After dioClient.updateToken() - Duration: ${swUp.elapsedMilliseconds} ms', name: 'AuthTrace');

        return accessToken;
      }
      throw Exception('Login failed with status ${response.statusCode}');
    } on DioException catch (e) {
      dev.log('[AUTH][STEP-14-ERR] DioException during login: type=${e.type}, status=${e.response?.statusCode}', name: 'AuthTrace');
      throw _parseDioException(e);
    } catch (e, stack) {
      dev.log('[AUTH][STEP-14-EXC] Catch-all Exception during login: $e\n$stack', name: 'AuthTrace');
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
    }
    return Exception(e.message ?? 'Authentication error occurred.');
  }

  Future<void> logout() async {
    final sw = Stopwatch()..start();
    dev.log('[AUTH][STEP-20] Before logout secureStorage.delete()', name: 'AuthTrace');
    await _secureStorage.delete(key: _tokenKey);
    await _secureStorage.delete(key: _refreshTokenKey);
    await _secureStorage.delete(key: _userIdKey);
    await _secureStorage.delete(key: _loginTimestampKey);
    await _dioClient.updateToken(null);
    sw.stop();
    dev.log('[AUTH][STEP-20] After logout secureStorage.delete() - Duration: ${sw.elapsedMilliseconds} ms', name: 'AuthTrace');
  }
}
