import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nearby_frontend/features/nearby/presentation/nearby_screen.dart';
import 'package:nearby_frontend/features/chat/data/chat_repository.dart';
import 'package:nearby_frontend/features/chat/presentation/chat_controller.dart';
import 'package:nearby_frontend/core/database/entities/message_entity.dart';

class FakeChatRepository implements ChatRepository {
  @override
  String? activeRoomId;

  @override
  Stream<MessageEntity> get incomingMessages => const Stream.empty();

  @override
  String get currentUserId => 'test-user-id';

  @override
  Future<void> updateCurrentUserId(String userId) async {}

  @override
  Future<void> ensureConnected([String? token]) async {}

  @override
  Future<String> getOrCreateRoom(String userA, String userB) async => 'test-room';

  @override
  Stream<List<MessageEntity>> watchMessages(String roomId) => Stream.value([]);

  @override
  Future<void> sendMessage(String roomId, String text) async {}

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
