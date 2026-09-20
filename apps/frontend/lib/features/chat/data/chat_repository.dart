import 'dart:async';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/crypto/crypto_service.dart';
import '../../../core/database/entities/message_entity.dart';
import '../../../core/database/isar_service.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/network/environment.dart';
import '../../../core/network/websocket_client.dart';
import '../domain/chat_message_payload.dart';
import '../domain/chat_request.dart';
import 'audio_player_service.dart';

class ChatRepository {
  final IsarService _storage;
  final DioClient _dioClient;
  final WebSocketClient _wsClient;
  final FlutterSecureStorage _secureStorage;
  final CryptoService _cryptoService;
  String _currentUserId;
  String? activeRoomId;
  StreamSubscription<Map<String, dynamic>>? _wsSubscription;
  final StreamController<MessageEntity> _incomingMessageController = StreamController<MessageEntity>.broadcast();
  final StreamController<Map<String, dynamic>> _profileUpdateController = StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<ChatRequest> _chatRequestController = StreamController<ChatRequest>.broadcast();
  final Map<String, Map<String, String>> _peerKeysCache = {};
  final Map<String, ChatMessagePayload> _plaintextCache = {};

  /// Explicitly clears volatile in-memory plaintext cache on session termination or logout
  void clearVolatileCache() {
    _plaintextCache.clear();
  }

  Stream<MessageEntity> get incomingMessages => _incomingMessageController.stream;
  Stream<Map<String, dynamic>> get profileUpdates => _profileUpdateController.stream;
  Stream<ChatRequest> get chatRequests => _chatRequestController.stream;
  CryptoService get cryptoService => _cryptoService;

  ChatRepository({
    required IsarService isar,
    required DioClient dioClient,
    required WebSocketClient wsClient,
    required String currentUserId,
    FlutterSecureStorage secureStorage = const FlutterSecureStorage(),
    CryptoService? cryptoService,
  })  : _storage = isar,
        _dioClient = dioClient,
        _wsClient = wsClient,
        _currentUserId = currentUserId,
        _secureStorage = secureStorage,
        _cryptoService = cryptoService ?? CryptoService(secureStorage: secureStorage);

  String get currentUserId => _currentUserId;

  Future<void> updateCurrentUserId(String userId) async {
    _currentUserId = userId;
  }

  /// Registers user's public identity and signed prekey on the backend for E2EE session discovery.
  Future<void> registerCryptoKeys() async {
    try {
      final bundle = await _cryptoService.getPublicIdentityBundle();
      await _dioClient.dio.post('/chat/keys', data: bundle);
    } catch (_) {}
  }

  /// Fetches target peer's public E2EE identity bundle.
  Future<Map<String, String>?> getPeerKeys(String peerId) async {
    if (_peerKeysCache.containsKey(peerId)) {
      return _peerKeysCache[peerId];
    }
    try {
      final response = await _dioClient.dio.get('/chat/keys/$peerId');
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        final keys = {
          'identity_key_pub': data['identity_key_pub'] as String? ?? '',
          'signed_prekey_pub': data['signed_prekey_pub'] as String? ?? '',
          'signed_prekey_sig': data['signed_prekey_sig'] as String? ?? '',
        };
        _peerKeysCache[peerId] = keys;
        return keys;
      }
    } catch (_) {}
    return null;
  }

  Future<void> ensureConnected([String? token]) async {
    if (!_wsClient.isConnected) {
      final activeToken = token ?? await _secureStorage.read(key: 'jwt_access_token');
      final activeUserId = await _secureStorage.read(key: 'authenticated_user_id');
      if (activeUserId != null && activeUserId.isNotEmpty) {
        _currentUserId = activeUserId;
      }
      if (activeToken != null && activeToken.isNotEmpty) {
        startWebSocketListener(activeToken);
        await registerCryptoKeys();
      }
    }
  }

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

  // --- CHAT REQUEST API METHODS ---

  // Sends a new chat request to recipient
  Future<ChatRequest> sendChatRequest(String recipientId) async {
    final response = await _dioClient.dio.post(
      '/chat/requests',
      data: {
        'recipient_id': recipientId,
      },
    );
    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = response.data as Map<String, dynamic>;
      final req = ChatRequest.fromJson(data);
      _chatRequestController.add(req);
      return req;
    }
    throw Exception('Failed to send chat request: ${response.statusMessage}');
  }

  // Fetches all incoming pending requests for the authenticated user
  Future<List<ChatRequest>> getPendingRequests() async {
    final response = await _dioClient.dio.get('/chat/requests/pending');
    if (response.statusCode == 200) {
      final list = response.data as List<dynamic>;
      return list.map((item) => ChatRequest.fromJson(item as Map<String, dynamic>)).toList();
    }
    throw Exception('Failed to fetch pending requests: ${response.statusMessage}');
  }

  // Gets the latest request status between authenticated user and a peer
  Future<ChatRequest?> getRequestStatus(String peerId) async {
    try {
      final response = await _dioClient.dio.get(
        '/chat/requests/status',
        queryParameters: {'peer_id': peerId},
      );
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        if (data.isEmpty || data['status'] == null) return null;
        return ChatRequest.fromJson(data);
      }
    } catch (_) {
      // No active or previous request found
    }
    return null;
  }

  // Accepts a pending chat request, activating the room
  Future<ChatRequest> acceptChatRequest(String requestId) async {
    final response = await _dioClient.dio.post('/chat/requests/$requestId/accept');
    if (response.statusCode == 200) {
      final data = response.data as Map<String, dynamic>;
      final req = ChatRequest.fromJson(data);
      _chatRequestController.add(req);
      return req;
    }
    throw Exception('Failed to accept chat request: ${response.statusMessage}');
  }

  // Denies a pending chat request, closing any associated session
  Future<ChatRequest> denyChatRequest(String requestId) async {
    final response = await _dioClient.dio.post('/chat/requests/$requestId/deny');
    if (response.statusCode == 200) {
      final data = response.data as Map<String, dynamic>;
      final req = ChatRequest.fromJson(data);
      _chatRequestController.add(req);
      return req;
    }
    throw Exception('Failed to deny chat request: ${response.statusMessage}');
  }

  // Fetches a request by ID
  Future<ChatRequest?> getChatRequestById(String requestId) async {
    final response = await _dioClient.dio.get('/chat/requests/$requestId');
    if (response.statusCode == 200 && response.data != null) {
      return ChatRequest.fromJson(response.data as Map<String, dynamic>);
    }
    return null;
  }

  // Watch messages reactively from database cache
  Stream<List<MessageEntity>> watchMessages(String roomId) {
    return _storage.watchMessages(roomId);
  }

  // Send message with True Application-Layer End-to-End Encryption
  Future<void> sendMessage(String roomId, ChatMessagePayload payload, {String? peerId}) async {
    await ensureConnected();
    final messageId = const Uuid().v4();
    final idempotencyKey = const Uuid().v4();
    final plainBytes = payload.toBytes();
    final plaintextJson = utf8.decode(plainBytes);

    List<int> payloadBytes;

    // Encrypt payload using Double Ratchet session
    if (peerId != null && peerId.isNotEmpty) {
      final peerKeys = await getPeerKeys(peerId);
      if (peerKeys != null && peerKeys['signed_prekey_pub']!.isNotEmpty) {
        await _cryptoService.getOrCreateSession(
          roomId: roomId,
          peerId: peerId,
          peerIdentityPubBase64: peerKeys['identity_key_pub']!,
          peerSignedPrekeyPubBase64: peerKeys['signed_prekey_pub']!,
          peerSignedPrekeySigBase64: peerKeys['signed_prekey_sig'] ?? '',
          isInitiator: true,
        );
      }
    }

    final session = _cryptoService.getSession(roomId);
    if (session == null) {
      throw CryptoException('Failed to encrypt: No active Double Ratchet session for room $roomId');
    }

    payloadBytes = await _cryptoService.encryptMessage(
      roomId: roomId,
      plaintextJson: plaintextJson,
    );

    // Cache plaintext in volatile memory ONLY for local display during active session.
    // Zero plaintext at rest: plaintext is NEVER written to disk or persistent storage.
    _plaintextCache[messageId] = payload;

    final messageEntity = MessageEntity()
      ..messageId = messageId
      ..roomId = roomId
      ..senderId = _currentUserId
      ..encryptedPayload = payloadBytes
      ..idempotencyKey = idempotencyKey
      ..createdAt = DateTime.now();

    // 1. Save locally via storage abstraction
    await _storage.saveMessage(messageEntity);

    // 2. Dispatch asynchronously to server via WebSocket (server receives opaque ciphertext)
    if (_wsClient.isConnected) {
      final base64Payload = base64Encode(payloadBytes);
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
    }
  }

  // Decrypts message entity payload using Double Ratchet session
  // Prohibits automatic plaintext fallback.
  Future<ChatMessagePayload> decryptPayload(MessageEntity entity, {String? peerId}) async {
    // 1. Check in-memory volatile plaintext cache
    if (_plaintextCache.containsKey(entity.messageId)) {
      return _plaintextCache[entity.messageId]!;
    }

    // 2. Prevent self-decryption: Outgoing messages use local sending chain CKs and DH ratchet.
    // Attempting to run decryptMessage on self-sent messages violates Signal Double Ratchet protocol
    // and corrupts the state machine.
    if (entity.senderId == _currentUserId) {
      return ChatMessagePayload.plainText('[Sent message]');
    }

    final rawString = utf8.decode(entity.encryptedPayload, allowMalformed: true);
    if (!rawString.startsWith('E2EE:v2:') && !rawString.startsWith('E2EE:v1:')) {
      return ChatMessagePayload.plainText('🔒 [Unauthenticated / Invalid Message]');
    }

    try {
      if (peerId != null && peerId.isNotEmpty) {
        final peerKeys = await getPeerKeys(peerId);
        if (peerKeys != null && peerKeys['signed_prekey_pub']!.isNotEmpty) {
          await _cryptoService.getOrCreateSession(
            roomId: entity.roomId,
            peerId: peerId,
            peerIdentityPubBase64: peerKeys['identity_key_pub']!,
            peerSignedPrekeyPubBase64: peerKeys['signed_prekey_pub']!,
            peerSignedPrekeySigBase64: peerKeys['signed_prekey_sig'] ?? '',
            isInitiator: false,
          );
        }
      }

      final decryptedJson = await _cryptoService.decryptMessage(
        roomId: entity.roomId,
        rawBytes: entity.encryptedPayload,
      );
      final decryptedPayload = ChatMessagePayload.fromBytes(utf8.encode(decryptedJson));
      // Store ONLY in volatile in-memory cache for the current session
      _plaintextCache[entity.messageId] = decryptedPayload;
      return decryptedPayload;
    } catch (_) {
      return ChatMessagePayload.plainText('🔒 [Decryption Failed: Authentication Error]');
    }
  }

  // Delete message for me: removes from local Isar database and stops audio if active
  Future<void> deleteMessageForMe(String roomId, String messageId) async {
    _plaintextCache.remove(messageId);
    unawaited(_secureStorage.delete(key: 'msg_plain_$messageId'));
    await _storage.deleteMessage(messageId);
    AudioPlayerService.stop();
  }

  // Delete message for everyone: authorizes and executes durable deletion across all clients
  Future<void> deleteMessageForEveryone(String roomId, String messageId) async {
    _plaintextCache.remove(messageId);
    unawaited(_secureStorage.delete(key: 'msg_plain_$messageId'));
    // 1. Remove locally immediately
    await _storage.deleteMessage(messageId);
    AudioPlayerService.stop();

    // 2. Transmit deletion frame via WebSocket
    if (_wsClient.isConnected) {
      _wsClient.send({
        'type': 'DELETE_MESSAGE',
        'room_id': roomId,
        'message_id': messageId,
        'delete_type': 'FOR_EVERYONE',
        'delete_message': {
          'message_id': messageId,
          'room_id': roomId,
        },
      });
    }

    // 3. Redundant durable HTTP deletion call to guarantee persistence
    try {
      await _dioClient.dio.delete(
        '/chat/messages/$messageId',
        queryParameters: {'room_id': roomId},
      );
    } catch (_) {}
  }

  // Subscribes to the WebSocket server cluster inbox using JWT token (fixes CRIT-06)
  void startWebSocketListener(String token) {
    if (token.isEmpty) return;
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
            decodedPayload = utf8.encode(payload);
          }

          final entity = MessageEntity()
            ..messageId = messageId
            ..roomId = roomId
            ..senderId = senderId
            ..encryptedPayload = decodedPayload
            ..idempotencyKey = msgData['idempotency_key'] ?? ''
            ..createdAt = DateTime.tryParse(msgData['created_at'] as String? ?? '') ?? DateTime.now();

          // Save received message to database cache via storage abstraction
          await _storage.saveMessage(entity);

          // Emit to global UI incoming messages broadcast stream
          _incomingMessageController.add(entity);

          // Reply with message delivery ACK receipt
          sendReadReceipt(roomId, messageId, 'DELIVERED');
        }
      } else if (type == 'MESSAGE_DELETED') {
        final delData = event['delete_message'] as Map<String, dynamic>?;
        final delMsgId = delData?['message_id'] as String? ?? event['message_id'] as String?;
        if (delMsgId != null && delMsgId.isNotEmpty) {
          _plaintextCache.remove(delMsgId);
          unawaited(_secureStorage.delete(key: 'msg_plain_$delMsgId'));
          await _storage.deleteMessage(delMsgId);
          AudioPlayerService.stop();
        }
      } else if (type == 'PROFILE_UPDATED') {
        _profileUpdateController.add(event);
      } else if (type == 'CHAT_REQUEST_RECEIVED' || type == 'CHAT_REQUEST_ACCEPTED' || type == 'CHAT_REQUEST_DENIED') {
        final reqData = event['chat_request'] as Map<String, dynamic>?;
        if (reqData != null) {
          final chatReq = ChatRequest.fromJson(reqData);
          _chatRequestController.add(chatReq);
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
    _wsSubscription?.cancel();
    _wsSubscription = null;
    _incomingMessageController.close();
    _profileUpdateController.close();
    _chatRequestController.close();
    _wsClient.close();
  }
}
