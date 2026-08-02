import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';
import 'package:nearby_frontend/core/network/dio_client.dart';
import 'package:nearby_frontend/features/auth/data/auth_repository.dart';

class FakeDioAdapter implements HttpClientAdapter {
  late Response Function(RequestOptions options) onRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final response = onRequest(options);
    final responseData = response.data;
    final jsonString = responseData is String
        ? responseData
        : jsonEncode(responseData);

    return ResponseBody.fromString(
      jsonString,
      response.statusCode ?? 200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class FakeFlutterSecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String> _storage = {};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return _storage[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value != null) {
      _storage[key] = value;
    } else {
      _storage.remove(key);
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _storage.remove(key);
  }

  bool hasKey(String key) => _storage.containsKey(key);
  String? getValue(String key) => _storage[key];
}

class TestableDioClient implements DioClient {
  final Dio _customDio;

  TestableDioClient(this._customDio);

  @override
  Dio get dio => _customDio;

  @override
  Future<void> updateToken(String? token) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFlutterSecureStorage fakeSecureStorage;
  late Dio dio;
  late TestableDioClient testableDioClient;
  late AuthRepository authRepository;

  setUp(() {
    fakeSecureStorage = FakeFlutterSecureStorage();
    dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8090/api/v1'));
    testableDioClient = TestableDioClient(dio);

    authRepository = AuthRepository(
      dioClient: testableDioClient,
      secureStorage: fakeSecureStorage,
    );
  });

  group('AuthRepository State Machine Unit Tests', () {
    test('First-time Registration (HTTP 201) triggers login successfully', () async {
      await fakeSecureStorage.write(key: 'device_hardware_id', value: 'dev_mock_001');

      dio.httpClientAdapter = _createMockAdapter((options) {
        if (options.path.contains('/auth/register')) {
          return Response(
            requestOptions: options,
            statusCode: 201,
            data: {'id': 'user_uuid_100', 'pseudonym': 'user-100'},
          );
        }
        if (options.path.contains('/auth/login')) {
          return Response(
            requestOptions: options,
            statusCode: 200,
            data: {
              'access_token': 'jwt_access_201_token',
              'refresh_token': 'jwt_refresh_201_token'
            },
          );
        }
        return Response(requestOptions: options, statusCode: 404);
      });

      await authRepository.registerAndLogin('Password123!');

      expect(fakeSecureStorage.getValue('jwt_access_token'), equals('jwt_access_201_token'));
      expect(fakeSecureStorage.getValue('jwt_refresh_token'), equals('jwt_refresh_201_token'));
      expect(fakeSecureStorage.hasKey('authenticated_login_timestamp'), isTrue);
    });

    test('Already Registered Device (HTTP 409) automatically executes login without error', () async {
      await fakeSecureStorage.write(key: 'device_hardware_id', value: 'dev_mock_409');

      dio.httpClientAdapter = _createMockAdapter((options) {
        if (options.path.contains('/auth/register')) {
          throw DioException(
            requestOptions: options,
            response: Response(
              requestOptions: options,
              statusCode: 409,
              data: {'error': 'device already registered'},
            ),
          );
        }
        if (options.path.contains('/auth/login')) {
          return Response(
            requestOptions: options,
            statusCode: 200,
            data: {
              'access_token': 'jwt_access_409_token',
              'refresh_token': 'jwt_refresh_409_token'
            },
          );
        }
        return Response(requestOptions: options, statusCode: 404);
      });

      await authRepository.registerAndLogin('Password123!');

      expect(fakeSecureStorage.getValue('jwt_access_token'), equals('jwt_access_409_token'));
      expect(fakeSecureStorage.getValue('jwt_refresh_token'), equals('jwt_refresh_409_token'));
    });

    test('Invalid Credentials (HTTP 401) throws specific error message', () async {
      await fakeSecureStorage.write(key: 'device_hardware_id', value: 'dev_mock_401');

      dio.httpClientAdapter = _createMockAdapter((options) {
        throw DioException(
          requestOptions: options,
          response: Response(
            requestOptions: options,
            statusCode: 401,
            data: {'error': 'Invalid credentials provided.'},
          ),
        );
      });

      expect(
        () async => await authRepository.login('WrongPass'),
        throwsA(predicate((e) => e.toString().contains('Invalid credentials provided.'))),
      );
    });

    test('Offline Connection Refused Error throws actionable error message', () async {
      await fakeSecureStorage.write(key: 'device_hardware_id', value: 'dev_mock_offline');

      dio.httpClientAdapter = _createMockAdapter((options) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      });

      expect(
        () async => await authRepository.login('Password123!'),
        throwsA(predicate((e) => e.toString().contains('Unable to connect to Gateway'))),
      );
    });
  });
}

HttpClientAdapter _createMockAdapter(Response Function(RequestOptions options) handler) {
  final adapter = FakeDioAdapter();
  adapter.onRequest = handler;
  return adapter;
}
