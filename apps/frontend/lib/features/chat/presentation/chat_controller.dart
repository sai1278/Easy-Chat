import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/entities/message_entity.dart';
import '../../nearby/domain/proximity_user.dart';
import '../data/chat_repository.dart';
import '../data/media_repository.dart';
import '../domain/chat_message_payload.dart';
import '../domain/chat_request.dart';
import 'chat_session_args.dart';

// Class representing the composite state of a Chat Room session
class ChatState {
  final List<MessageEntity> messages;
  final bool isRecipientTyping;
  final bool isRecipientOnline;
  final String? lastReadMessageId;
  final ChatRequestStatus requestStatus;
  /// Non-null when a media upload failed. Cleared after the UI reads it.
  final String? uploadError;
  /// True while an attachment upload is in-flight.
  final bool isUploading;

  const ChatState({
    required this.messages,
    this.isRecipientTyping = false,
    this.isRecipientOnline = false,
    this.lastReadMessageId,
    this.requestStatus = ChatRequestStatus.accepted,
    this.uploadError,
    this.isUploading = false,
  });

  ChatState copyWith({
    List<MessageEntity>? messages,
    bool? isRecipientTyping,
    bool? isRecipientOnline,
    String? lastReadMessageId,
    ChatRequestStatus? requestStatus,
    String? uploadError,
    bool clearUploadError = false,
    bool? isUploading,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isRecipientTyping: isRecipientTyping ?? this.isRecipientTyping,
      isRecipientOnline: isRecipientOnline ?? this.isRecipientOnline,
      lastReadMessageId: lastReadMessageId ?? this.lastReadMessageId,
      requestStatus: requestStatus ?? this.requestStatus,
      uploadError: clearUploadError ? null : (uploadError ?? this.uploadError),
      isUploading: isUploading ?? this.isUploading,
    );
  }
}

// Stub repository provider (initialized in main.dart)
final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  throw UnimplementedError('Initialize this provider inside main.dart');
});

// Stream provider for incoming real-time chat requests
final incomingChatRequestStreamProvider = StreamProvider<ChatRequest>((ref) {
  final repo = ref.watch(chatRepositoryProvider);
  return repo.chatRequests;
});

// StateNotifierProvider parameterized by ChatSessionArgs to manage chat sessions
final chatControllerProvider = StateNotifierProvider.family<ChatController, ChatState, ChatSessionArgs>((ref, args) {
  final repository = ref.watch(chatRepositoryProvider);
  return ChatController(
    repository: repository,
    roomId: args.roomId,
    peerId: args.peerId,
    initialStatus: args.requestStatus,
    ref: ref,
  );
});

class ChatController extends StateNotifier<ChatState> {
  final ChatRepository _repository;
  final MediaRepository _mediaRepository;
  final String _roomId;
  final String _peerId;
  final Ref _ref;
  StreamSubscription<List<MessageEntity>>? _messageSubscription;
  StreamSubscription<ChatRequest>? _requestSubscription;

  ChatController({
    required ChatRepository repository,
    MediaRepository? mediaRepository,
    required String roomId,
    required String peerId,
    ChatRequestStatus initialStatus = ChatRequestStatus.accepted,
    required Ref ref,
  })  : _repository = repository,
        _mediaRepository = mediaRepository ?? MediaRepository(),
        _roomId = roomId,
        _peerId = peerId,
        _ref = ref,
        super(ChatState(messages: const [], requestStatus: initialStatus)) {
    _init();
  }

  void _init() {
    _repository.activeRoomId = _roomId;
    _repository.ensureConnected();

    // 1. Subscribe to reactive local Isar database cache messages stream
    _messageSubscription = _repository.watchMessages(_roomId).listen((messagesList) {
      state = state.copyWith(messages: messagesList);
      if (messagesList.isNotEmpty) {
        final lastMsg = messagesList.last;
        if (lastMsg.senderId != _repository.currentUserId) {
          markMessagesAsRead(lastMsg.messageId);
        }
      }
    });

    // 2. Fetch presence online status from discovered proximity list
    final users = _ref.read(proximityUsersProvider);
    final isOnline = users.any((u) => u.userId == _peerId && u.isOnline);
    state = state.copyWith(isRecipientOnline: isOnline);

    // 3. Fetch latest chat request status between current user and peer
    _fetchCurrentRequestStatus();

    // 4. Listen to real-time chat request events
    _requestSubscription = _repository.chatRequests.listen((req) {
      if ((req.senderId == _peerId && req.recipientId == _repository.currentUserId) ||
          (req.senderId == _repository.currentUserId && req.recipientId == _peerId)) {
        state = state.copyWith(requestStatus: req.status);
      }
    });
  }

  Future<void> _fetchCurrentRequestStatus() async {
    try {
      final req = await _repository.getRequestStatus(_peerId);
      if (req != null) {
        state = state.copyWith(requestStatus: req.status);
      }
    } catch (_) {}
  }

  Future<void> sendChatMessage(String text) async {
    if (text.trim().isEmpty) return;
    if (state.requestStatus != ChatRequestStatus.accepted) return;
    // Encode as typed plain-text payload (backward-compat JSON envelope)
    final payload = ChatMessagePayload.plainText(text);
    await _repository.sendMessage(_roomId, payload, peerId: _peerId);
  }

  // ---------------------------------------------------------------------------
  // Attachment send methods
  // ---------------------------------------------------------------------------

  /// Upload [imageFile] from device storage, encrypt locally, and deliver as an E2EE IMAGE message.
  Future<void> sendImageMessage(File imageFile) async {
    if (state.requestStatus != ChatRequestStatus.accepted) return;
    state = state.copyWith(isUploading: true, clearUploadError: true);
    try {
      final result = await _mediaRepository.uploadEncryptedFile(
        imageFile,
        _repository.cryptoService,
        roomId: _roomId,
      );
      final payload = ChatMessagePayload.image(
        mediaUrl: result.url,
        mediaFileId: result.fileId,
        mediaKey: result.mediaKey,
        mediaNonce: result.mediaNonce,
      );
      await _repository.sendMessage(_roomId, payload, peerId: _peerId);
    } catch (e) {
      state = state.copyWith(
        isUploading: false,
        uploadError: e is MediaUploadException ? e.message : 'Image upload failed',
      );
      return;
    }
    state = state.copyWith(isUploading: false);
  }

  /// Upload [audioFile] recorded on device, encrypt locally, and deliver as an E2EE VOICE message.
  Future<void> sendVoiceMessage(File audioFile, {int? durationSeconds}) async {
    if (state.requestStatus != ChatRequestStatus.accepted) return;
    state = state.copyWith(isUploading: true, clearUploadError: true);
    try {
      final result = await _mediaRepository.uploadEncryptedFile(
        audioFile,
        _repository.cryptoService,
        roomId: _roomId,
      );
      final payload = ChatMessagePayload.voice(
        mediaUrl: result.url,
        mediaFileId: result.fileId,
        durationSeconds: durationSeconds,
        mediaKey: result.mediaKey,
        mediaNonce: result.mediaNonce,
      );
      await _repository.sendMessage(_roomId, payload, peerId: _peerId);
    } catch (e) {
      state = state.copyWith(
        isUploading: false,
        uploadError: e is MediaUploadException ? e.message : 'Voice upload failed',
      );
      return;
    }
    state = state.copyWith(isUploading: false);
  }

  /// Deliver the sender's current GPS coordinates as an E2EE LOCATION message.
  /// No file upload required — lat/lng is encoded in the E2EE envelope.
  Future<void> sendLocationMessage(double latitude, double longitude) async {
    if (state.requestStatus != ChatRequestStatus.accepted) return;
    final payload = ChatMessagePayload.location(
      latitude: latitude,
      longitude: longitude,
    );
    await _repository.sendMessage(_roomId, payload, peerId: _peerId);
  }

  /// Delete message for me: removes from local Isar database.
  Future<void> deleteMessageForMe(MessageEntity message) async {
    await _repository.deleteMessageForMe(_roomId, message.messageId);
  }

  /// Delete message for everyone: deletes on server, wipes ciphertext, propagates tombstone.
  Future<void> deleteMessageForEveryone(MessageEntity message) async {
    await _repository.deleteMessageForEveryone(_roomId, message.messageId);
  }

  /// Decrypts message entity payload using E2EE session key or legacy fallback.
  Future<ChatMessagePayload> decryptPayload(MessageEntity message) async {
    return await _repository.decryptPayload(message, peerId: _peerId);
  }

  /// Clear a previously surfaced upload error after the UI has shown it.
  void clearUploadError() {
    state = state.copyWith(clearUploadError: true);
  }

  void sendTypingState(bool isTyping) {
    if (state.requestStatus != ChatRequestStatus.accepted) return;
    _repository.sendTypingIndicator(_roomId, isTyping);
  }

  void markMessagesAsRead(String lastMessageId) {
    _repository.sendReadReceipt(_roomId, lastMessageId, 'READ');
    state = state.copyWith(lastReadMessageId: lastMessageId);
  }

  @override
  void dispose() {
    if (_repository.activeRoomId == _roomId) {
      _repository.activeRoomId = null;
    }
    _messageSubscription?.cancel();
    _requestSubscription?.cancel();
    super.dispose();
  }
}
