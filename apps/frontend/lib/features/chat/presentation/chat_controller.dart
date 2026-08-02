import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/entities/message_entity.dart';
import '../../nearby/domain/proximity_user.dart';
import '../data/chat_repository.dart';
import 'chat_session_args.dart';

// Class representing the composite state of a Chat Room session
class ChatState {
  final List<MessageEntity> messages;
  final bool isRecipientTyping;
  final bool isRecipientOnline;
  final String? lastReadMessageId;

  const ChatState({
    required this.messages,
    this.isRecipientTyping = false,
    this.isRecipientOnline = false,
    this.lastReadMessageId,
  });

  ChatState copyWith({
    List<MessageEntity>? messages,
    bool? isRecipientTyping,
    bool? isRecipientOnline,
    String? lastReadMessageId,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isRecipientTyping: isRecipientTyping ?? this.isRecipientTyping,
      isRecipientOnline: isRecipientOnline ?? this.isRecipientOnline,
      lastReadMessageId: lastReadMessageId ?? this.lastReadMessageId,
    );
  }
}

// Stub repository provider (initialized in main.dart)
final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  throw UnimplementedError('Initialize this provider inside main.dart');
});

// StateNotifierProvider parameterized by ChatSessionArgs to manage chat sessions
final chatControllerProvider = StateNotifierProvider.family<ChatController, ChatState, ChatSessionArgs>((ref, args) {
  final repository = ref.watch(chatRepositoryProvider);
  return ChatController(repository: repository, roomId: args.roomId, peerId: args.peerId, ref: ref);
});

class ChatController extends StateNotifier<ChatState> {
  final ChatRepository _repository;
  final String _roomId;
  final String _peerId;
  final Ref _ref;
  StreamSubscription<List<MessageEntity>>? _messageSubscription;

  ChatController({
    required ChatRepository repository,
    required String roomId,
    required String peerId,
    required Ref ref,
  })  : _repository = repository,
        _roomId = roomId,
        _peerId = peerId,
        _ref = ref,
        super(const ChatState(messages: [])) {
    _init();
  }

  void _init() {
    _repository.activeRoomId = _roomId;
    _repository.ensureConnected();
    // 1. Subscribe to reactive local Isar database cache messages stream (fixes HIGH-11).
    _messageSubscription = _repository.watchMessages(_roomId).listen((messagesList) {
      state = state.copyWith(messages: messagesList);
      if (messagesList.isNotEmpty) {
        final lastMsg = messagesList.last;
        // Use real current user ID instead of hardcoded self_user (fixes MED-13).
        if (lastMsg.senderId != _repository.currentUserId) {
          markMessagesAsRead(lastMsg.messageId);
        }
      }
    });

    // 2. Fetch presence online status from discovered proximity list
    final users = _ref.read(proximityUsersProvider);
    final isOnline = users.any((u) => u.userId == _peerId && u.isOnline);
    state = state.copyWith(isRecipientOnline: isOnline);
  }

  Future<void> sendChatMessage(String text) async {
    if (text.trim().isEmpty) return;
    await _repository.sendMessage(_roomId, text);
  }

  void sendTypingState(bool isTyping) {
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
    // Cancel Isar subscription to prevent memory leaks and setState after dispose (fixes HIGH-11).
    _messageSubscription?.cancel();
    super.dispose();
  }
}
