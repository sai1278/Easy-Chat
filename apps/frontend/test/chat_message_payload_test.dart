import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:nearby_frontend/features/chat/domain/chat_message_payload.dart';

void main() {
  group('ChatMessagePayload Unit Tests', () {
    test('Plain text serialization and deserialization', () {
      final payload = ChatMessagePayload.plainText('Hello, world! 🚀');
      final bytes = payload.toBytes();
      final decoded = ChatMessagePayload.fromBytes(bytes);

      expect(decoded.type, equals(MessageType.text));
      expect(decoded.text, equals('Hello, world! 🚀'));
    });

    test('Legacy plain-text fallback (raw non-JSON bytes)', () {
      final rawBytes = utf8.encode('Old plain text without JSON wrapper');
      final decoded = ChatMessagePayload.fromBytes(rawBytes);

      expect(decoded.type, equals(MessageType.text));
      expect(decoded.text, equals('Old plain text without JSON wrapper'));
    });

    test('Image payload serialization and deserialization', () {
      final payload = ChatMessagePayload.image(
        mediaUrl: 'http://192.168.1.2:8090/api/v1/media/img-12345',
        mediaFileId: 'img-12345',
      );
      final bytes = payload.toBytes();
      final decoded = ChatMessagePayload.fromBytes(bytes);

      expect(decoded.type, equals(MessageType.image));
      expect(decoded.mediaUrl, equals('http://192.168.1.2:8090/api/v1/media/img-12345'));
      expect(decoded.mediaFileId, equals('img-12345'));
    });

    test('Voice payload serialization and deserialization with duration', () {
      final payload = ChatMessagePayload.voice(
        mediaUrl: 'http://192.168.1.2:8090/api/v1/media/audio-999',
        mediaFileId: 'audio-999',
        durationSeconds: 12,
      );
      final bytes = payload.toBytes();
      final decoded = ChatMessagePayload.fromBytes(bytes);

      expect(decoded.type, equals(MessageType.voice));
      expect(decoded.mediaUrl, equals('http://192.168.1.2:8090/api/v1/media/audio-999'));
      expect(decoded.mediaFileId, equals('audio-999'));
      expect(decoded.durationSeconds, equals(12));
    });

    test('Location payload serialization and deserialization with coordinates', () {
      final payload = ChatMessagePayload.location(
        latitude: 17.448293,
        longitude: 78.391485,
        locationLabel: 'Current Location',
      );
      final bytes = payload.toBytes();
      final decoded = ChatMessagePayload.fromBytes(bytes);

      expect(decoded.type, equals(MessageType.location));
      expect(decoded.latitude, closeTo(17.448293, 0.000001));
      expect(decoded.longitude, closeTo(78.391485, 0.000001));
      expect(decoded.locationLabel, equals('Current Location'));
    });

    test('Malformed JSON gracefully falls back to text', () {
      final malformedBytes = utf8.encode('{"type": "image", broken_json');
      final decoded = ChatMessagePayload.fromBytes(malformedBytes);

      expect(decoded.type, equals(MessageType.text));
      expect(decoded.text, equals('{"type": "image", broken_json'));
    });

    test('Empty bytes gracefully fallback to empty text', () {
      final emptyBytes = <int>[];
      final decoded = ChatMessagePayload.fromBytes(emptyBytes);

      expect(decoded.type, equals(MessageType.text));
      expect(decoded.text, isEmpty);
    });
  });
}
