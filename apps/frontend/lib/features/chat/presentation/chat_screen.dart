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

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.blueGrey.shade100,
              child: Text(widget.peerId.isNotEmpty ? widget.peerId[0].toUpperCase() : 'C'),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Chat with ${widget.peerId.toUpperCase()}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: chatState.isRecipientOnline ? Colors.green : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      chatState.isRecipientOnline ? 'online' : 'offline',
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          // Connection status/offline banner
          if (!chatState.isRecipientOnline)
            Container(
              color: Colors.amber.shade100,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: const Center(
                child: Text(
                  'Offline session: messages will sync on reconnect',
                  style: TextStyle(fontSize: 11, color: Colors.brown),
                ),
              ),
            ),

          // Messages list
          Expanded(
            child: chatState.messages.isEmpty
                ? const Center(
                    child: Text(
                      'No ephemeral messages. Secure conversation initiated.',
                      style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
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
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.grey),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Recipient is typing...',
                      style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),

          // Message input bar
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    focusNode: _focusNode,
                    onChanged: (text) {
                      _setTyping(text.isNotEmpty);
                    },
                    decoration: const InputDecoration(
                      hintText: 'Enter secure message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(24)),
                      ),
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.blue),
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
    return Align(
      alignment: isSelf ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelf ? Colors.blue.shade100 : Colors.grey.shade200,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(isSelf ? 12 : 0),
            bottomRight: Radius.circular(isSelf ? 0 : 12),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isSelf ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(text),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 8, color: Colors.grey),
                ),
                if (isSelf) ...[
                  const SizedBox(width: 4),
                  Icon(
                    isRead ? Icons.done_all : Icons.done,
                    size: 10,
                    color: isRead ? Colors.blue : Colors.grey,
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
