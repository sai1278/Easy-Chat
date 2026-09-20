// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nearby_frontend/main.dart';
import 'package:nearby_frontend/core/network/websocket_client.dart';
import 'package:nearby_frontend/core/database/entities/message_entity.dart';
import 'package:nearby_frontend/features/chat/domain/chat_message_payload.dart';
import 'package:nearby_frontend/features/chat/data/chat_repository.dart';
import 'package:nearby_frontend/features/chat/domain/chat_request.dart';
import 'package:nearby_frontend/core/crypto/crypto_service.dart';
import 'package:nearby_frontend/features/chat/presentation/chat_controller.dart';

// Minimal fake WebSocketClient for testing
class FakeWebSocketClient implements WebSocketClient {
  bool _isConnected = false;
  final StreamController<Map<String, dynamic>> _streamController =
      StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> get stream => _streamController.stream;

  @override
  bool get isConnected => _isConnected;

  @override
  void connect(String url, {required String token}) {
    _isConnected = true;
  }

  @override
  void send(Map<String, dynamic> packet) {
    // No-op for testing
  }

  @override
  void setHeartbeatInterval(Duration interval) {
    // No-op for testing
  }

  @override
  void close() {
    _isConnected = false;
    _streamController.close();
  }
}

// Minimal fake ChatRepository for testing
class FakeChatRepository implements ChatRepository {
  @override
  String? activeRoomId;

  @override
  void clearVolatileCache() {}

  @override
  Stream<MessageEntity> get incomingMessages => const Stream.empty();

  @override
  Stream<Map<String, dynamic>> get profileUpdates => const Stream.empty();

  @override
  CryptoService get cryptoService => CryptoService();

  @override
  String get currentUserId => 'test-user-id';

  @override
  Future<void> updateCurrentUserId(String userId) async {}

  @override
  Future<void> registerCryptoKeys() async {}

  @override
  Future<Map<String, String>?> getPeerKeys(String peerId) async => null;

  @override
  Future<void> ensureConnected([String? token]) async {}

  @override
  Future<String> getOrCreateRoom(String userA, String userB) async {
    return 'test-room-id';
  }

  @override
  Stream<List<MessageEntity>> watchMessages(String roomId) {
    return Stream.value([]);
  }

  @override
  Future<void> sendMessage(String roomId, ChatMessagePayload payload, {String? peerId}) async {
    // No-op for testing
  }

  @override
  Future<ChatMessagePayload> decryptPayload(MessageEntity entity, {String? peerId}) async {
    return ChatMessagePayload.fromBytes(entity.encryptedPayload);
  }

  @override
  Future<void> deleteMessageForMe(String roomId, String messageId) async {}

  @override
  Future<void> deleteMessageForEveryone(String roomId, String messageId) async {}

  @override
  void startWebSocketListener(String token) {
    // No-op for testing
  }

  @override
  void sendReadReceipt(String roomId, String messageId, String status) {
    // No-op for testing
  }

  @override
  void sendTypingIndicator(String roomId, bool isTyping) {
    // No-op for testing
  }

  @override
  Stream<ChatRequest> get chatRequests => const Stream.empty();

  @override
  Future<ChatRequest> sendChatRequest(String recipientId) async {
    return ChatRequest(
      id: 'test-req-id',
      senderId: currentUserId,
      recipientId: recipientId,
      status: ChatRequestStatus.pending,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<List<ChatRequest>> getPendingRequests() async {
    return [];
  }

  @override
  Future<ChatRequest?> getRequestStatus(String peerId) async {
    return null;
  }

  @override
  Future<ChatRequest> acceptChatRequest(String requestId) async {
    return ChatRequest(
      id: requestId,
      senderId: 'peer-id',
      recipientId: currentUserId,
      roomId: 'test-room-id',
      status: ChatRequestStatus.accepted,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<ChatRequest> denyChatRequest(String requestId) async {
    return ChatRequest(
      id: requestId,
      senderId: 'peer-id',
      recipientId: currentUserId,
      status: ChatRequestStatus.denied,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<ChatRequest?> getChatRequestById(String requestId) async {
    return null;
  }

  @override
  void close() {
    // No-op for testing
  }
}

void main() {
  testWidgets('App builds smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
          webSocketClientProvider.overrideWithValue(FakeWebSocketClient()),
        ],
        child: const NearbyConnectApp(),
      ),
    );

    // Verify that MaterialApp is present
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
