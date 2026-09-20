import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/crypto/crypto_service.dart';
import '../../../core/network/environment.dart';

/// Response returned after a successful media upload.
class MediaUploadResult {
  final String fileId;
  final String url;
  final String? mediaKey;
  final String? mediaNonce;

  const MediaUploadResult({
    required this.fileId,
    required this.url,
    this.mediaKey,
    this.mediaNonce,
  });

  factory MediaUploadResult.fromJson(Map<String, dynamic> json, {String? mediaKey, String? mediaNonce}) {
    final cfg = ApiConfig.fromEnvironment();
    final fileId = json['file_id'] as String? ?? '';
    var rawUrl = json['url'] as String? ?? '';
    if (rawUrl.startsWith('/')) {
      rawUrl = '${cfg.httpScheme}://${cfg.host}:${cfg.gatewayPort}$rawUrl';
    } else if (rawUrl.isEmpty && fileId.isNotEmpty) {
      rawUrl = '${cfg.httpScheme}://${cfg.host}:${cfg.gatewayPort}/api/v1/media/download/$fileId';
    }
    return MediaUploadResult(
      fileId: fileId,
      url: rawUrl,
      mediaKey: mediaKey,
      mediaNonce: mediaNonce,
    );
  }
}

/// Handles multipart encrypted media uploads and authenticated downloads to the media service.
class MediaRepository {
  final FlutterSecureStorage _secureStorage;
  late final Dio _dio;

  MediaRepository({
    FlutterSecureStorage secureStorage = const FlutterSecureStorage(),
  }) : _secureStorage = secureStorage {
    final cfg = ApiConfig.fromEnvironment();
    _dio = Dio(
      BaseOptions(
        baseUrl: cfg.baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
        sendTimeout: const Duration(seconds: 60),
      ),
    );
  }

  /// Encrypt [file] locally with single-use AES-256-GCM and upload ciphertext.
  /// Attaches [roomId] and [messageId] for zero-trust backend authorization.
  Future<MediaUploadResult> uploadEncryptedFile(
    File file,
    CryptoService cryptoService, {
    String? roomId,
    String? messageId,
  }) async {
    final token = await _secureStorage.read(key: 'jwt_access_token');
    if (token == null || token.isEmpty) {
      throw const MediaUploadException('Not authenticated: JWT token missing');
    }

    // 1. Read raw bytes and encrypt locally with single-use AES-256-GCM
    final rawBytes = await file.readAsBytes();
    final encResult = await cryptoService.encryptAttachment(rawBytes);

    // 2. Prepare multipart request containing ciphertext and authorization metadata
    final fileName = file.path.split(Platform.pathSeparator).last;
    final formMap = <String, dynamic>{
      'file': MultipartFile.fromBytes(
        encResult.ciphertext,
        filename: 'enc_$fileName',
      ),
    };
    if (roomId != null && roomId.isNotEmpty) {
      formMap['room_id'] = roomId;
    }
    if (messageId != null && messageId.isNotEmpty) {
      formMap['message_id'] = messageId;
    }
    final formData = FormData.fromMap(formMap);

    final headers = <String, dynamic>{
      'Authorization': 'Bearer $token',
    };
    if (roomId != null && roomId.isNotEmpty) {
      headers['X-Room-Id'] = roomId;
    }
    if (messageId != null && messageId.isNotEmpty) {
      headers['X-Message-Id'] = messageId;
    }

    try {
      final cfg = ApiConfig.fromEnvironment();
      final response = await _dio.post(
        '${cfg.baseUrl}/media/upload',
        data: formData,
        options: Options(
          headers: headers,
        ),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data as Map<String, dynamic>;
        final baseResult = MediaUploadResult.fromJson(data);
        return MediaUploadResult(
          fileId: baseResult.fileId,
          url: baseResult.url,
          mediaKey: encResult.mediaKeyBase64,
          mediaNonce: encResult.nonceBase64,
        );
      }
      throw MediaUploadException(
        'Upload failed: HTTP ${response.statusCode} — ${response.statusMessage}',
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 400) {
        final body = e.response?.data;
        final errorMsg = body is Map ? (body['error'] ?? 'Bad request') : 'Bad request';
        throw MediaUploadException('Upload rejected: $errorMsg');
      }
      if (e.response?.statusCode == 403) {
        throw const MediaUploadException('Upload forbidden: you are not an authorized member of this chat room');
      }
      if (e.response?.statusCode == 413) {
        throw const MediaUploadException('File too large: maximum 10 MB allowed');
      }
      throw MediaUploadException('Upload error: ${e.message}');
    }
  }

  // In-memory decrypted media cache (avoids writing plaintext images to disk)
  final Map<String, Uint8List> _decryptedMemoryCache = {};

  /// Downloads encrypted media blob and decrypts strictly in volatile memory.
  /// Zero plaintext at rest: bytes exist only in RAM.
  /// Enforces room and message membership authorization parameters.
  Future<Uint8List> downloadAndDecryptMediaBytes({
    required String fileId,
    required String mediaKey,
    required String mediaNonce,
    required CryptoService cryptoService,
    String? roomId,
    String? messageId,
  }) async {
    if (_decryptedMemoryCache.containsKey(fileId)) {
      return _decryptedMemoryCache[fileId]!;
    }

    final token = await _secureStorage.read(key: 'jwt_access_token');
    if (token == null || token.isEmpty) {
      throw const MediaUploadException('Not authenticated: JWT token missing');
    }

    final cfg = ApiConfig.fromEnvironment();
    final queryParams = <String, String>{};
    if (roomId != null && roomId.isNotEmpty) queryParams['room_id'] = roomId;
    if (messageId != null && messageId.isNotEmpty) queryParams['message_id'] = messageId;

    final headers = <String, dynamic>{
      'Authorization': 'Bearer $token',
    };
    if (roomId != null && roomId.isNotEmpty) headers['X-Room-Id'] = roomId;
    if (messageId != null && messageId.isNotEmpty) headers['X-Message-Id'] = messageId;

    final uri = Uri.parse('${cfg.baseUrl}/media/download/$fileId').replace(
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
    );

    final response = await _dio.get<List<int>>(
      uri.toString(),
      options: Options(
        responseType: ResponseType.bytes,
        headers: headers,
      ),
    );

    if (response.statusCode == 200 && response.data != null) {
      final decryptedBytes = await cryptoService.decryptAttachment(
        ciphertextBytes: response.data!,
        mediaKeyBase64: mediaKey,
        nonceBase64: mediaNonce,
      );
      final u8List = Uint8List.fromList(decryptedBytes);
      _decryptedMemoryCache[fileId] = u8List;
      return u8List;
    }
    throw MediaUploadException('Failed to download media: HTTP ${response.statusCode}');
  }

  /// Downloads encrypted media blob, decrypts locally, and stores ephemeral file in system temp cache for audio player.
  Future<File> downloadAndDecryptMedia({
    required String fileId,
    required String mediaKey,
    required String mediaNonce,
    required CryptoService cryptoService,
    String? roomId,
    String? messageId,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final cacheFile = File('${tempDir.path}/ephemeral_media_$fileId.tmp');
    if (await cacheFile.exists() && await cacheFile.length() > 0) {
      return cacheFile;
    }

    final bytes = await downloadAndDecryptMediaBytes(
      fileId: fileId,
      mediaKey: mediaKey,
      mediaNonce: mediaNonce,
      cryptoService: cryptoService,
      roomId: roomId,
      messageId: messageId,
    );
    await cacheFile.writeAsBytes(bytes, flush: true);
    return cacheFile;
  }

  /// Deletes media on server and purges local memory & ephemeral disk cache.
  Future<void> deleteMedia(String fileId) async {
    // 1. Purge memory cache
    _decryptedMemoryCache.remove(fileId);

    // 2. Delete local temp file if present
    try {
      final tempDir = await getTemporaryDirectory();
      final cacheFile = File('${tempDir.path}/ephemeral_media_$fileId.tmp');
      if (await cacheFile.exists()) {
        await cacheFile.delete();
      }
    } catch (_) {}
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final legacyFile = File('${docsDir.path}/e2ee_media_$fileId.dec');
      if (await legacyFile.exists()) {
        await legacyFile.delete();
      }
    } catch (_) {}

    // 3. Delete on media service
    final token = await _secureStorage.read(key: 'jwt_access_token');
    if (token == null || token.isEmpty) return;

    try {
      final cfg = ApiConfig.fromEnvironment();
      await _dio.delete(
        '${cfg.baseUrl}/media/$fileId',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
    } catch (_) {}
  }
}

class MediaUploadException implements Exception {
  final String message;
  const MediaUploadException(this.message);

  @override
  String toString() => 'MediaUploadException: $message';
}
