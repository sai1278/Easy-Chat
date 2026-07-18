import 'dart:async';
import 'dart:convert';
import 'package:isar/isar.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/entities/message_entity.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/network/environment.dart';
import '../../../core/network/websocket_client.dart';

class ChatRepository {
  final Isar _isar;
  final DioClient _dioClient;
  final WebSocketClient _wsClient;
  final String _currentUserId;
  StreamSubscription<Map<String, dynamic>>? _wsSubscription;

  ChatRepository({
    required Isar isar,
    required DioClient dioClient,
    required WebSocketClient wsClient,
    required String currentUserId,
  })  : _isar = isar,
        _dioClient = dioClient,
        _wsClient = wsClient,
        _currentUserId = currentUserId;

  String get currentUserId => _currentUserId;

  // Resolves or creates a mutually unique active chat room via REST API
  Future<String> getOrCreateRoom(String userA, String userB) async {
    final response = await _dioClient.dio.post(
      '/chat/rooms',
      data: {
        'userA': userA,
        'userB': userB,
      },
    );
    if (response.statusCode == 200) {
      final data = response.data as Map<String, dynamic>;
      return data['roomId'] as String;
    }
    throw Exception('Failed to resolve room ID: ${response.statusMessage}');
  }

  // Watch messages reactively from Isar database cache
  Stream<List<MessageEntity>> watchMessages(String roomId) {
    return _isar.messageEntitys
        .filter()
        .roomIdEqualTo(roomId)
        .sortByCreatedAt()
        .watch(fireImmediately: true);
  }

  // Send message using write-through cache: save locally first, then sync over API
  Future<void> sendMessage(String roomId, String text) async {
    final messageId = const Uuid().v4();
    final idempotencyKey = const Uuid().v4();
    final payloadBytes = List<int>.from(text.codeUnits); // Encrypted payload mockup bytes

    final messageEntity = MessageEntity()
      ..messageId = messageId
      ..roomId = roomId
      ..senderId = _currentUserId // Use real current user ID instead of hardcoded self_user (fixes MED-12)
      ..encryptedPayload = payloadBytes
      ..idempotencyKey = idempotencyKey
      ..createdAt = DateTime.now();

    // 1. Save locally in Isar
    await _isar.writeTxn(() async {
      await _isar.messageEntitys.put(messageEntity);
    });

    // 2. Dispatch asynchronously to server via WebSocket
    if (_wsClient.isConnected) {
      final base64Payload = base64Encode(text.codeUnits);
      _wsClient.send({
        'type': 'MESSAGE',
        'message': {
          'message_id': messageId,
          'room_id': roomId,
          'sender_id': _currentUserId,
          'encrypted_payload': base64Payload,
          'idempotency_key': idempotencyKey,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        }
      });
    } else {
      // Fallback/offline: message remains in Isar local cache
    }
  }

  // Subscribes to the WebSocket server cluster inbox using JWT token (fixes CRIT-06)
  void startWebSocketListener(String token) {
    final wsUrl = ApiConfig.fromEnvironment().wsUrl;
    _wsClient.connect(wsUrl, token: token);
    
    // Store subscription to prevent leaks and double-listens (fixes HIGH-09)
    _wsSubscription?.cancel();
    _wsSubscription = _wsClient.stream.listen((event) async {
      final type = event['type'] as String?;
      if (type == 'MESSAGE') {
        final msgData = event['message'] as Map<String, dynamic>?;
        if (msgData != null) {
          final messageId = msgData['message_id'] as String;
          final roomId = msgData['room_id'] as String;
          final senderId = msgData['sender_id'] as String;
          final payload = msgData['encrypted_payload'] as String;

          List<int> decodedPayload;
          try {
            decodedPayload = base64Decode(payload);
          } catch (_) {
            decodedPayload = List<int>.from(payload.codeUnits);
          }

          final entity = MessageEntity()
            ..messageId = messageId
            ..roomId = roomId
            ..senderId = senderId
            ..encryptedPayload = decodedPayload
            ..idempotencyKey = msgData['idempotency_key'] ?? ''
            ..createdAt = DateTime.tryParse(msgData['created_at'] as String? ?? '') ?? DateTime.now();

          // Save received message to Isar database cache
          await _isar.writeTxn(() async {
            await _isar.messageEntitys.put(entity);
          });

          // Reply with message delivery ACK receipt
          sendReadReceipt(roomId, messageId, 'DELIVERED');
        }
      }
    });
  }

  // Send a delivery or read receipt acknowledgement
  void sendReadReceipt(String roomId, String messageId, String status) {
    _wsClient.send({
      'type': 'RECEIPT',
      'receipt': {
        'message_id': messageId,
        'room_id': roomId,
        'status': status,
        'timestamp': DateTime.now().toIso8601String(),
      }
    });
  }

  // Send transient user typing event (bypasses persistent database caches)
  void sendTypingIndicator(String roomId, bool isTyping) {
    _wsClient.send({
      'type': 'TYPING',
      'typing': {
        'room_id': roomId,
        'is_typing': isTyping,
      }
    });
  }

  void close() {
    _wsSubscription?.cancel(); // Cancel stream subscription to prevent leaks (fixes HIGH-09)
    _wsSubscription = null;
    _wsClient.close();
  }
}
