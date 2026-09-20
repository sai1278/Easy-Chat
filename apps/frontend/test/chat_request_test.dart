import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:nearby_frontend/features/chat/domain/chat_request.dart';

void main() {
  group('ChatRequestStatus Tests', () {
    test('parses status correctly from string', () {
      expect(ChatRequestStatus.fromString('PENDING'), ChatRequestStatus.pending);
      expect(ChatRequestStatus.fromString('pending'), ChatRequestStatus.pending);
      expect(ChatRequestStatus.fromString('ACCEPTED'), ChatRequestStatus.accepted);
      expect(ChatRequestStatus.fromString('accepted'), ChatRequestStatus.accepted);
      expect(ChatRequestStatus.fromString('DENIED'), ChatRequestStatus.denied);
      expect(ChatRequestStatus.fromString('denied'), ChatRequestStatus.denied);
      expect(ChatRequestStatus.fromString('CANCELLED'), ChatRequestStatus.cancelled);
      expect(ChatRequestStatus.fromString('cancelled'), ChatRequestStatus.cancelled);
      expect(ChatRequestStatus.fromString('UNKNOWN'), ChatRequestStatus.none);
      expect(ChatRequestStatus.fromString(null), ChatRequestStatus.none);
    });

    test('serializes status value string correctly', () {
      expect(ChatRequestStatus.pending.value, 'PENDING');
      expect(ChatRequestStatus.accepted.value, 'ACCEPTED');
      expect(ChatRequestStatus.denied.value, 'DENIED');
      expect(ChatRequestStatus.cancelled.value, 'CANCELLED');
      expect(ChatRequestStatus.none.value, 'NONE');
    });
  });

  group('ChatRequest Domain Model Tests', () {
    test('fromJson and toJson deserializes and serializes accurately', () {
      final now = DateTime.utc(2026, 9, 9, 12, 30, 0);
      final json = {
        'id': '01900000-0000-7000-8000-000000000001',
        'sender_id': '01900000-0000-7000-8000-000000000002',
        'recipient_id': '01900000-0000-7000-8000-000000000003',
        'room_id': '01900000-0000-7000-8000-000000000004',
        'status': 'PENDING',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
        'sender_display_name': 'Sai Tester ✨',
        'sender_username': 'saitest',
        'sender_avatar_url': 'https://example.com/avatar.png',
        'sender_bio': 'Building distributed P2P chat systems 🚀',
      };

      final req = ChatRequest.fromJson(json);

      expect(req.id, '01900000-0000-7000-8000-000000000001');
      expect(req.senderId, '01900000-0000-7000-8000-000000000002');
      expect(req.recipientId, '01900000-0000-7000-8000-000000000003');
      expect(req.roomId, '01900000-0000-7000-8000-000000000004');
      expect(req.status, ChatRequestStatus.pending);
      expect(req.senderDisplayName, 'Sai Tester ✨');
      expect(req.senderBio, 'Building distributed P2P chat systems 🚀');

      final serialized = req.toJson();
      expect(serialized['status'], 'PENDING');
      expect(serialized['sender_display_name'], 'Sai Tester ✨');
      expect(serialized['sender_bio'], 'Building distributed P2P chat systems 🚀');
    });

    test('supports camelCase json fallback from REST responses', () {
      final json = {
        'id': 'req-123',
        'senderId': 'user-a',
        'recipientId': 'user-b',
        'roomId': 'room-xyz',
        'status': 'ACCEPTED',
        'createdAt': '2026-09-09T10:00:00Z',
        'updatedAt': '2026-09-09T10:05:00Z',
        'senderDisplayName': 'Alice',
      };

      final req = ChatRequest.fromJson(json);
      expect(req.id, 'req-123');
      expect(req.senderId, 'user-a');
      expect(req.recipientId, 'user-b');
      expect(req.roomId, 'room-xyz');
      expect(req.status, ChatRequestStatus.accepted);
      expect(req.senderDisplayName, 'Alice');
    });
  });

  group('UTF-8 Payload Preservation Tests', () {
    test('preserves emojis, multilingual scripts, and currency symbols across Base64 codec', () {
      final testStrings = [
        '😀 🚀 ❤️ 🎉 🌟 🛰️ 💻 ⚡',
        'नमस्ते EasyChat! यह एक परीक्षण संदेश है।',
        'مرحبا بك في تطبيق الدردشة السريعة!',
        '你好，欢迎使用附近聊天！',
        'Price: €49.99 / ₹3,999.00 © 2026 All Rights Reserved ® ™',
      ];

      for (final original in testStrings) {
        // Encoding as performed in ChatRepository
        final utf8Bytes = utf8.encode(original);
        final base64Payload = base64Encode(utf8Bytes);

        // Decoding as performed in ChatScreen and WebSocket listener
        final decodedBytes = base64Decode(base64Payload);
        final reconstructed = utf8.decode(decodedBytes, allowMalformed: true);

        expect(reconstructed, equals(original),
            reason: 'UTF-8 string should perfectly match original without byte corruption');
      }
    });
  });
}
