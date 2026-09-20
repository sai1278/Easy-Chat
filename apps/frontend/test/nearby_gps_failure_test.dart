import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nearby_frontend/features/nearby/presentation/nearby_screen.dart';
import 'package:nearby_frontend/features/chat/data/chat_repository.dart';
import 'package:nearby_frontend/features/chat/presentation/chat_controller.dart';
import 'package:nearby_frontend/core/database/entities/message_entity.dart';
import 'package:nearby_frontend/features/chat/domain/chat_message_payload.dart';
import 'package:nearby_frontend/features/chat/domain/chat_request.dart';

import 'package:nearby_frontend/core/crypto/crypto_service.dart';

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
  Stream<ChatRequest> get chatRequests => const Stream.empty();

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
  Future<String> getOrCreateRoom(String userA, String userB) async => 'test-room';

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
  Future<List<ChatRequest>> getPendingRequests() async => [];

  @override
  Future<ChatRequest?> getRequestStatus(String peerId) async => null;

  @override
  Future<ChatRequest> acceptChatRequest(String requestId) async {
    return ChatRequest(
      id: requestId,
      senderId: 'peer-id',
      recipientId: currentUserId,
      roomId: 'test-room',
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
  Future<ChatRequest?> getChatRequestById(String requestId) async => null;

  @override
  Stream<List<MessageEntity>> watchMessages(String roomId) => Stream.value([]);

  @override
  Future<void> sendMessage(String roomId, ChatMessagePayload payload, {String? peerId}) async {}

  @override
  Future<ChatMessagePayload> decryptPayload(MessageEntity entity, {String? peerId}) async {
    return ChatMessagePayload.fromBytes(entity.encryptedPayload);
  }

  @override
  Future<void> deleteMessageForMe(String roomId, String messageId) async {}

  @override
  Future<void> deleteMessageForEveryone(String roomId, String messageId) async {}

  @override
  void startWebSocketListener(String token) {}

  @override
  void sendReadReceipt(String roomId, String messageId, String status) {}

  @override
  void sendTypingIndicator(String roomId, bool isTyping) {}

  @override
  void close() {}
}

void main() {
  testWidgets('NearbyScreen GPS Failure Test: Does not display hardcoded fallback 17.3850/78.4867', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
        ],
        child: const MaterialApp(
          home: NearbyScreen(),
        ),
      ),
    );

    await tester.pump();

    // Verify hardcoded fallback 17.3850, 78.4867 is NEVER displayed in UI
    expect(find.textContaining('17.3850'), findsNothing);
    expect(find.textContaining('78.4867'), findsNothing);
  });
}
