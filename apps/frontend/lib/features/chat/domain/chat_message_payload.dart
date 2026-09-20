import 'dart:convert';
import '../../../core/network/environment.dart';

/// Discriminated-union payload envelope stored as UTF-8 JSON inside
/// [MessageEntity.encryptedPayload]. Existing plain-text messages decode
/// into [MessageType.text] for backward compatibility.
enum MessageType { text, image, voice, location }

class ChatMessagePayload {
  final MessageType type;

  /// For [MessageType.text] — the message body.
  final String? text;

  /// For [MessageType.image] / [MessageType.voice] — gateway-accessible URL.
  final String? mediaUrl;

  /// For [MessageType.image] / [MessageType.voice] — server-assigned file ID.
  final String? mediaFileId;

  /// For [MessageType.voice] — duration in seconds.
  final int? durationSeconds;

  /// For [MessageType.location].
  final double? latitude;
  final double? longitude;

  /// Human-readable place name (optional, resolved client-side).
  final String? locationLabel;

  /// For [MessageType.image] / [MessageType.voice] — ephemeral AES-GCM key and nonce
  final String? mediaKey;
  final String? mediaNonce;

  const ChatMessagePayload({
    required this.type,
    this.text,
    this.mediaUrl,
    this.mediaFileId,
    this.durationSeconds,
    this.latitude,
    this.longitude,
    this.locationLabel,
    this.mediaKey,
    this.mediaNonce,
  });


  /// Automatically resolves relative paths (e.g. /api/v1/media/download/...)
  /// or server file IDs into fully qualified LAN URLs for UI rendering.
  String? get resolvedMediaUrl {
    var raw = mediaUrl;
    if ((raw == null || raw.isEmpty) && mediaFileId != null && mediaFileId!.isNotEmpty) {
      raw = '/api/v1/media/download/$mediaFileId';
    }
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('/')) {
      final cfg = ApiConfig.fromEnvironment();
      return '${cfg.httpScheme}://${cfg.host}:${cfg.gatewayPort}$raw';
    }
    return raw;
  }

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
        'type': type.name,
        if (text != null) 'text': text,
        if (mediaUrl != null) 'media_url': mediaUrl,
        if (mediaFileId != null) 'media_file_id': mediaFileId,
        if (durationSeconds != null) 'duration_seconds': durationSeconds,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (locationLabel != null) 'location_label': locationLabel,
        if (mediaKey != null) 'media_key': mediaKey,
        if (mediaNonce != null) 'media_nonce': mediaNonce,
      };

  /// Encode to UTF-8 bytes for storage in [MessageEntity.encryptedPayload].
  List<int> toBytes() => utf8.encode(jsonEncode(toJson()));

  // ---------------------------------------------------------------------------
  // Deserialization
  // ---------------------------------------------------------------------------

  /// Decode from [MessageEntity.encryptedPayload] bytes.
  ///
  /// If the bytes do not contain a valid JSON object with a `type` key (i.e.,
  /// they are a legacy plain-text message), returns a [MessageType.text]
  /// payload where [text] is the raw decoded string.
  static ChatMessagePayload fromBytes(List<int> bytes) {
    try {
      final raw = utf8.decode(bytes, allowMalformed: true);
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final typeName = map['type'] as String?;
      final type = MessageType.values.firstWhere(
        (e) => e.name == typeName,
        orElse: () => MessageType.text,
      );
      return ChatMessagePayload(
        type: type,
        text: map['text'] as String?,
        mediaUrl: map['media_url'] as String?,
        mediaFileId: map['media_file_id'] as String?,
        durationSeconds: map['duration_seconds'] as int?,
        latitude: (map['latitude'] as num?)?.toDouble(),
        longitude: (map['longitude'] as num?)?.toDouble(),
        locationLabel: map['location_label'] as String?,
        mediaKey: map['media_key'] as String?,
        mediaNonce: map['media_nonce'] as String?,
      );
    } catch (_) {
      // Legacy plain-text message — treat entire bytes as UTF-8 text.
      return ChatMessagePayload(
        type: MessageType.text,
        text: utf8.decode(bytes, allowMalformed: true),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Factory helpers
  // ---------------------------------------------------------------------------

  static ChatMessagePayload plainText(String text) =>
      ChatMessagePayload(type: MessageType.text, text: text);

  static ChatMessagePayload image({
    required String mediaUrl,
    required String mediaFileId,
    String? mediaKey,
    String? mediaNonce,
  }) =>
      ChatMessagePayload(
        type: MessageType.image,
        mediaUrl: mediaUrl,
        mediaFileId: mediaFileId,
        mediaKey: mediaKey,
        mediaNonce: mediaNonce,
      );

  static ChatMessagePayload voice({
    required String mediaUrl,
    required String mediaFileId,
    int? durationSeconds,
    String? mediaKey,
    String? mediaNonce,
  }) =>
      ChatMessagePayload(
        type: MessageType.voice,
        mediaUrl: mediaUrl,
        mediaFileId: mediaFileId,
        durationSeconds: durationSeconds,
        mediaKey: mediaKey,
        mediaNonce: mediaNonce,
      );

  static ChatMessagePayload location({
    required double latitude,
    required double longitude,
    String? locationLabel,
  }) =>
      ChatMessagePayload(
        type: MessageType.location,
        latitude: latitude,
        longitude: longitude,
        locationLabel: locationLabel,
      );

}
