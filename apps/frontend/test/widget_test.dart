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
import 'package:nearby_frontend/features/chat/data/chat_repository.dart';
import 'package:nearby_frontend/features/chat/presentation/chat_controller.dart';

// Minimal fake WebSocketClient for testing
class FakeWebSocketClient {
  bool _isConnected = false;
  final StreamController<Map<String, dynamic>> _streamController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get stream => _streamController.stream;
  bool get isConnected => _isConnected;

  void connect(String url, {required String token}) {
    _isConnected = true;
  }

  void send(Map<String, dynamic> packet) {
    // No-op for testing
  }

  void setHeartbeatInterval(Duration interval) {
    // No-op for testing
  }

  void close() {
    _isConnected = false;
    _streamController.close();
  }
}

// Minimal fake ChatRepository for testing
class FakeChatRepository implements ChatRepository {
  @override
  String get currentUserId => 'test-user-id';

  @override
  Future<String> getOrCreateRoom(String userA, String userB) async {
    return 'test-room-id';
  }

  @override
  Stream<List<dynamic>> watchMessages(String roomId) {
    return Stream.value([]);
  }

  @override
  Future<void> sendMessage(String roomId, String text) async {
    // No-op for testing
  }

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
