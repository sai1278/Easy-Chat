import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'chat_controller.dart';
import 'chat_session_args.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String roomId;
  final String peerId;
  const ChatScreen({super.key, required this.roomId, required this.peerId});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus && _textController.text.isNotEmpty) {
      _setTyping(true);
    } else {
      _setTyping(false);
    }
  }

  void _setTyping(bool isTyping) {
    if (_isTyping != isTyping) {
      _isTyping = isTyping;
      ref.read(chatControllerProvider(ChatSessionArgs(roomId: widget.roomId, peerId: widget.peerId)).notifier).sendTypingState(isTyping);
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatControllerProvider(ChatSessionArgs(roomId: widget.roomId, peerId: widget.peerId)));
    final controller = ref.read(chatControllerProvider(ChatSessionArgs(roomId: widget.roomId, peerId: widget.peerId)).notifier);
    final currentUserId = ref.watch(chatRepositoryProvider).currentUserId;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: colorScheme.primaryContainer,
              child: Text(
                widget.peerId.isNotEmpty ? widget.peerId[0].toUpperCase() : 'C',
                style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.onPrimaryContainer),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.peerId.toUpperCase(),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: chatState.isRecipientOnline ? Colors.green : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      chatState.isRecipientOnline ? 'Active nearby' : 'Offline',
                      style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Connection status/offline banner
          if (!chatState.isRecipientOnline)
            Container(
              color: colorScheme.tertiaryContainer,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.sync_problem_rounded, size: 14, color: colorScheme.onTertiaryContainer),
                  const SizedBox(width: 6),
                  Text(
                    'Offline session: messages stored locally and synced on reconnect',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: colorScheme.onTertiaryContainer),
                  ),
                ],
              ),
            ),

          // Messages list
          Expanded(
            child: chatState.messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_outline_rounded, size: 40, color: colorScheme.onSurfaceVariant.withOpacity(0.5)),
                        const SizedBox(height: 12),
                        Text(
                          'End-to-End Encrypted Session',
                          style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Messages are ephemeral and transmitted over secure WebSocket.',
                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant.withOpacity(0.8)),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: chatState.messages.length,
                    itemBuilder: (context, index) {
                      final msg = chatState.messages[index];
                      final isSelf = msg.senderId == currentUserId;
                      final text = String.fromCharCodes(msg.encryptedPayload);
                      final isRead = chatState.lastReadMessageId == msg.messageId;

                      return _MessageBubble(
                        key: ValueKey(msg.messageId),
                        text: text,
                        createdAt: msg.createdAt,
                        isSelf: isSelf,
                        isRead: isRead,
                      );
                    },
                  ),
          ),

          // Real-time recipient typing indicator header
          if (chatState.isRecipientTyping)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Peer is typing...',
                      style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: colorScheme.primary),
                    ),
                  ],
                ),
              ),
            ),

          // Material 3 Pill Message input bar
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 12, bottom: 12, top: 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    focusNode: _focusNode,
                    onChanged: (text) {
                      _setTyping(text.isNotEmpty);
                    },
                    decoration: InputDecoration(
                      hintText: 'Type secure message...',
                      hintStyle: TextStyle(color: colorScheme.onSurfaceVariant.withOpacity(0.7)),
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHigh,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: const Icon(Icons.send_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                  ),
                  onPressed: () {
                    final text = _textController.text;
                    if (text.trim().isNotEmpty) {
                      controller.sendChatMessage(text);
                      _textController.clear();
                      _setTyping(false);
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final String text;
  final DateTime createdAt;
  final bool isSelf;
  final bool isRead;

  const _MessageBubble({
    super.key,
    required this.text,
    required this.createdAt,
    required this.isSelf,
    required this.isRead,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Align(
      alignment: isSelf ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isSelf ? colorScheme.primaryContainer : colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isSelf ? 20 : 4),
            bottomRight: Radius.circular(isSelf ? 4 : 20),
          ),
        ),
        child: Column(
          crossAxisAlignment: isSelf ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: TextStyle(
                fontSize: 15,
                color: isSelf ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontSize: 10,
                    color: isSelf
                        ? colorScheme.onPrimaryContainer.withOpacity(0.7)
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
                if (isSelf) ...[
                  const SizedBox(width: 4),
                  Icon(
                    isRead ? Icons.done_all_rounded : Icons.done_rounded,
                    size: 14,
                    color: isRead ? colorScheme.primary : colorScheme.onPrimaryContainer.withOpacity(0.7),
                  ),
                ]
              ],
            ),
          ],
        ),
      ),
    );
  }
}
