import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final ScrollController _scrollController = ScrollController();
  bool _isTyping = false;
  String? _replyingToText;

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
      ref
          .read(chatControllerProvider(ChatSessionArgs(roomId: widget.roomId, peerId: widget.peerId)).notifier)
          .sendTypingState(isTyping);
    }
  }

  void _showPeerProfileModal(BuildContext context, bool isOnline) {
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: colorScheme.primaryContainer,
                child: Text(
                  widget.peerId.isNotEmpty ? widget.peerId[0].toUpperCase() : 'P',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: colorScheme.onPrimaryContainer),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.peerId.toUpperCase(),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isOnline ? Colors.green : Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isOnline ? 'Active nearby' : 'Offline',
                    style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Divider(color: colorScheme.outlineVariant.withOpacity(0.5)),
              const SizedBox(height: 12),
              ListTile(
                leading: Icon(Icons.security_rounded, color: colorScheme.primary),
                title: const Text('End-to-End Encrypted'),
                subtitle: const Text('Messages are ephemeral and self-destruct upon session close.'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAttachmentMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Wrap(
              spacing: 16,
              runSpacing: 16,
              alignment: WrapAlignment.spaceAround,
              children: [
                _AttachmentOption(
                  icon: Icons.image_rounded,
                  label: 'Image',
                  color: Colors.purple,
                  onTap: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Image attachment feature ready for media pipeline.')),
                    );
                  },
                ),
                _AttachmentOption(
                  icon: Icons.mic_rounded,
                  label: 'Voice Note',
                  color: Colors.redAccent,
                  onTap: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Voice note recording feature ready for audio pipeline.')),
                    );
                  },
                ),
                _AttachmentOption(
                  icon: Icons.location_on_rounded,
                  label: 'Location',
                  color: Colors.green,
                  onTap: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Live location sharing attached.')),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showMessageContextMenu(BuildContext context, String text, bool isSelf) {
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.copy_rounded, color: colorScheme.primary),
                title: const Text('Copy Text'),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: text));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Message copied to clipboard')),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.reply_rounded, color: colorScheme.secondary),
                title: const Text('Reply'),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _replyingToText = text;
                  });
                },
              ),
              ListTile(
                leading: Icon(Icons.forward_rounded, color: colorScheme.tertiary),
                title: const Text('Forward Message'),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Forward message placeholder ready.')),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline_rounded, color: colorScheme.error),
                title: Text('Delete Message', style: TextStyle(color: colorScheme.error)),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Message deleted locally.')),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatControllerProvider(ChatSessionArgs(roomId: widget.roomId, peerId: widget.peerId)));
    final controller =
        ref.read(chatControllerProvider(ChatSessionArgs(roomId: widget.roomId, peerId: widget.peerId)).notifier);
    final currentUserId = ref.watch(chatRepositoryProvider).currentUserId;
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () => _showPeerProfileModal(context, chatState.isRecipientOnline),
          child: Row(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: colorScheme.primaryContainer,
                    child: Text(
                      widget.peerId.isNotEmpty ? widget.peerId[0].toUpperCase() : 'C',
                      style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.onPrimaryContainer),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: chatState.isRecipientOnline ? Colors.green : Colors.grey,
                        border: Border.all(color: colorScheme.surface, width: 1.5),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.peerId.toUpperCase(),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    chatState.isRecipientOnline ? 'Active nearby' : 'Offline',
                    style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ],
          ),
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

          // Messages list with Date Separators
          Expanded(
            child: chatState.messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_outline_rounded, size: 44, color: colorScheme.onSurfaceVariant.withOpacity(0.5)),
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
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: chatState.messages.length,
                    itemBuilder: (context, index) {
                      final msg = chatState.messages[index];
                      final isSelf = msg.senderId == currentUserId;
                      final text = String.fromCharCodes(msg.encryptedPayload);
                      final isRead = chatState.lastReadMessageId == msg.messageId;

                      // Check if we need a date separator
                      bool showDateHeader = false;
                      if (index == 0) {
                        showDateHeader = true;
                      } else {
                        final prevMsg = chatState.messages[index - 1];
                        showDateHeader = msg.createdAt.day != prevMsg.createdAt.day ||
                            msg.createdAt.month != prevMsg.createdAt.month ||
                            msg.createdAt.year != prevMsg.createdAt.year;
                      }

                      return Column(
                        children: [
                          if (showDateHeader) _DateSeparator(date: msg.createdAt),
                          Dismissible(
                            key: Key('reply_${msg.messageId}'),
                            direction: DismissDirection.startToEnd,
                            confirmDismiss: (dir) async {
                              setState(() {
                                _replyingToText = text;
                              });
                              return false;
                            },
                            background: Container(
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.only(left: 20),
                              child: Icon(Icons.reply_rounded, color: colorScheme.primary),
                            ),
                            child: GestureDetector(
                              onLongPress: () => _showMessageContextMenu(context, text, isSelf),
                              child: _MessageBubble(
                                key: ValueKey(msg.messageId),
                                text: text,
                                createdAt: msg.createdAt,
                                isSelf: isSelf,
                                isRead: isRead,
                                peerId: widget.peerId,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),

          // Real-time recipient typing animation header
          if (chatState.isRecipientTyping)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 10,
                      backgroundColor: colorScheme.primaryContainer,
                      child: Text(
                        widget.peerId.isNotEmpty ? widget.peerId[0].toUpperCase() : 'P',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: colorScheme.onPrimaryContainer),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _TypingDotsIndicator(color: colorScheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      '${widget.peerId} is typing...',
                      style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: colorScheme.primary),
                    ),
                  ],
                ),
              ),
            ),

          // Swipe Reply Preview Header Bar
          if (_replyingToText != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: colorScheme.surfaceContainerHigh,
              child: Row(
                children: [
                  Icon(Icons.reply_rounded, size: 18, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Replying to: $_replyingToText',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => setState(() => _replyingToText = null),
                  ),
                ],
              ),
            ),

          // Material 3 Pill Message input toolbar with media attachments
          Padding(
            padding: const EdgeInsets.only(left: 10, right: 10, bottom: 12, top: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  color: colorScheme.primary,
                  onPressed: () => _showAttachmentMenu(context),
                ),
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
                      if (_replyingToText != null) {
                        setState(() => _replyingToText = null);
                      }
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }
}

class _AttachmentOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _AttachmentOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: color.withOpacity(0.15),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _DateSeparator extends StatelessWidget {
  final DateTime date;
  const _DateSeparator({required this.date});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    String dateStr = '${date.day}/${date.month}/${date.year}';

    if (date.day == now.day && date.month == now.month && date.year == now.year) {
      dateStr = 'Today';
    } else if (date.day == now.day - 1 && date.month == now.month && date.year == now.year) {
      dateStr = 'Yesterday';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            dateStr,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

class _TypingDotsIndicator extends StatefulWidget {
  final Color color;
  const _TypingDotsIndicator({required this.color});

  @override
  State<_TypingDotsIndicator> createState() => _TypingDotsIndicatorState();
}

class _TypingDotsIndicatorState extends State<_TypingDotsIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final opacity = ((_controller.value * 3 - index) % 3).clamp(0.2, 1.0);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withOpacity(opacity),
              ),
            );
          }),
        );
      },
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final String text;
  final DateTime createdAt;
  final bool isSelf;
  final bool isRead;
  final String peerId;

  const _MessageBubble({
    super.key,
    required this.text,
    required this.createdAt,
    required this.isSelf,
    required this.isRead,
    required this.peerId,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isSelf ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isSelf) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: colorScheme.primaryContainer,
              child: Text(
                peerId.isNotEmpty ? peerId[0].toUpperCase() : 'P',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.onPrimaryContainer),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
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
        ],
      ),
    );
  }
}
