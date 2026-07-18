import 'dart:math';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'environment.dart';

class _CacheEntry {
  final dynamic data;
  final String etag;
  final DateTime timestamp;

  _CacheEntry({
    required this.data,
    required this.etag,
    required this.timestamp,
  });
}

class HttpCache {
  final int maxEntries;
  final Duration ttl;
  final Map<String, _CacheEntry> _cacheMap = {};
  final List<String> _lruList = [];

  HttpCache({required this.maxEntries, required this.ttl});

  _CacheEntry? get(String key) {
    final entry = _cacheMap[key];
    if (entry == null) return null;

    // Check if expired
    if (DateTime.now().difference(entry.timestamp) > ttl) {
      remove(key);
      return null;
    }

    // Mark as recently used (LRU update)
    _lruList.remove(key);
    _lruList.add(key);
    return entry;
  }

  void put(String key, dynamic data, String etag) {
    // Evict expired entries first to optimize memory utilization
    _removeExpired();

    if (_cacheMap.containsKey(key)) {
      _lruList.remove(key);
    } else if (_cacheMap.length >= maxEntries) {
      // Evict oldest (LRU)
      final oldestKey = _lruList.first;
      remove(oldestKey);
    }

    _cacheMap[key] = _CacheEntry(
      data: data,
      etag: etag,
      timestamp: DateTime.now(),
    );
    _lruList.add(key);
  }

  void remove(String key) {
    _cacheMap.remove(key);
    _lruList.remove(key);
  }

  void _removeExpired() {
    final now = DateTime.now();
    final expiredKeys = <String>[];
    _cacheMap.forEach((key, entry) {
      if (now.difference(entry.timestamp) > ttl) {
        expiredKeys.add(key);
      }
    });
    for (final key in expiredKeys) {
      remove(key);
    }
  }

  void clear() {
    _cacheMap.clear();
    _lruList.clear();
  }

  int get size => _cacheMap.length;
}

class DioClient {
  late final Dio _dio;
  String? _cachedToken;
  bool _tokenLoaded = false;
  late final HttpCache _responseCache;

  DioClient({
    String? baseUrl,
    int maxCacheEntries = 100,
    Duration cacheTtl = const Duration(minutes: 5),
  }) {
    final effectiveBaseUrl = baseUrl ?? ApiConfig.fromEnvironment().baseUrl;
    _responseCache = HttpCache(maxEntries: maxCacheEntries, ttl: cacheTtl);
    _dio = Dio(
      BaseOptions(
        baseUrl: effectiveBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        validateStatus: (status) =>
            status != null &&
            ((status >= 200 && status < 300) || status == 304),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // 1. Inject Request correlation ID for tracing
          final requestId = const Uuid().v4();
          options.headers['X-Request-ID'] = requestId;

          // 2. Inject JWT Authorization header from cached in-memory token
          if (!_tokenLoaded) {
            final prefs = await SharedPreferences.getInstance();
            _cachedToken = prefs.getString('access_token');
            _tokenLoaded = true;
          }
          if (_cachedToken != null) {
            options.headers['Authorization'] = 'Bearer $_cachedToken';
          }

          // 3. Inject ETag cache validation header for GET requests
          if (options.method == 'GET') {
            final cached = _responseCache.get(options.path);
            if (cached != null) {
              options.headers['If-None-Match'] = cached.etag;
            }
          }

          return handler.next(options);
        },
        onResponse: (response, handler) {
          final requestMethod = response.requestOptions.method;
          final path = response.requestOptions.path;

          // Handle HTTP 304 Not Modified
          if (response.statusCode == 304) {
            final cached = _responseCache.get(path);
            if (cached != null) {
              return handler.resolve(
                Response(
                  requestOptions: response.requestOptions,
                  data: cached.data,
                  statusCode: 200,
                  headers: response.headers,
                ),
              );
            }
          }

          // Cache successful GET responses with ETags
          if (requestMethod == 'GET' && response.statusCode == 200) {
            final etag = response.headers.value('etag');
            if (etag != null) {
              _responseCache.put(path, response.data, etag);
            }
          }

          return handler.next(response);
        },
        onError: (DioException e, handler) async {
          // Identify transient network or server errors
          final isTransient = e.type == DioExceptionType.connectionTimeout ||
              e.type == DioExceptionType.sendTimeout ||
              e.type == DioExceptionType.receiveTimeout ||
              (e.response != null && e.response!.statusCode! >= 500);

          if (isTransient) {
            try {
              final response = await _retry(e.requestOptions);
              return handler.resolve(response);
            } catch (retryErr) {
              // If retry fails, forward the original exception
              return handler.next(e);
            }
          }

          return handler.next(e);
        },
      ),
    );
  }

  // Retries a request with exponential backoff and jitter
  Future<Response> _retry(RequestOptions requestOptions) async {
    const maxAttempts = 3;
    int attempt = 0;
    final random = Random();

    while (true) {
      attempt++;
      try {
        final options = Options(
          method: requestOptions.method,
          headers: requestOptions.headers,
        );
        return await _dio.request(
          requestOptions.path,
          data: requestOptions.data,
          queryParameters: requestOptions.queryParameters,
          options: options,
        );
      } catch (e) {
        if (attempt >= maxAttempts) {
          rethrow;
        }
        // Backoff: 2^attempt seconds + random jitter (0-500ms)
        final delayMs =
            (pow(2, attempt) * 1000).toInt() + random.nextInt(500);
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }
  }

  // Update token inside cached memory and SharedPreferences
  Future<void> updateToken(String? token) async {
    _cachedToken = token;
    _tokenLoaded = true;
    final prefs = await SharedPreferences.getInstance();
    if (token != null) {
      await prefs.setString('access_token', token);
    } else {
      await prefs.remove('access_token');
    }
  }

  Dio get dio => _dio;
}
