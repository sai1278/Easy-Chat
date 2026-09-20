import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import '../../../core/crypto/crypto_service.dart';
import '../../../core/database/entities/message_entity.dart';
import '../../../core/theme/clay_design_system.dart';
import '../../nearby/domain/proximity_user.dart';
import '../data/audio_player_service.dart';
import '../data/media_repository.dart';
import '../domain/chat_message_payload.dart';
import '../domain/chat_request.dart';
import 'chat_controller.dart';
import 'chat_session_args.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String roomId;
  final String peerId;
  final ChatRequestStatus initialStatus;

  const ChatScreen({
    super.key,
    required this.roomId,
    required this.peerId,
    this.initialStatus = ChatRequestStatus.accepted,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final Map<String, ChatMessagePayload> _decryptedPayloads = {};
  bool _isTyping = false;
  String? _replyingToText;
  bool _isLocating = false;

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
          .read(chatControllerProvider(ChatSessionArgs(
            roomId: widget.roomId,
            peerId: widget.peerId,
            requestStatus: widget.initialStatus,
          )).notifier)
          .sendTypingState(isTyping);
    }
  }

  void _showPeerProfileModal(BuildContext context, bool isOnline, String peerName) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: ClayColors.cardSurface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: ClayShadows.card,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 28.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: ClayColors.borderSubtle,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: ClayColors.accentLight,
                  shape: BoxShape.circle,
                  boxShadow: ClayShadows.card,
                ),
                child: Center(
                  child: Text(
                    peerName.isNotEmpty ? peerName[0].toUpperCase() : 'P',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: ClayColors.accent,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                peerName,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: ClayColors.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isOnline ? const Color(0xFF10B981) : const Color(0xFF9CA3AF),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isOnline ? 'Active nearby' : 'Offline',
                    style: TextStyle(fontSize: 13, color: ClayColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ClayCard(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: ClayColors.accentLight,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.shield_outlined, color: ClayColors.accent, size: 20),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Private Nearby Chat',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: ClayColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Messages are ephemeral and private between you and this nearby peer.',
                            style: TextStyle(fontSize: 12, color: ClayColors.textSecondary, height: 1.3),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  void _showAttachmentMenu(BuildContext context, ChatController controller) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
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
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _pickAndSendImage(controller);
                  },
                ),
                _AttachmentOption(
                  icon: Icons.mic_rounded,
                  label: 'Voice Note',
                  color: Colors.redAccent,
                  onTap: () {
                    Navigator.pop(ctx);
                    _openVoiceRecordingSheet(controller);
                  },
                ),
                _AttachmentOption(
                  icon: Icons.location_on_rounded,
                  label: 'Location',
                  color: Colors.green,
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _sendCurrentLocation(controller);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Image
  // ---------------------------------------------------------------------------

  Future<void> _pickAndSendImage(ChatController controller) async {
    // Let user choose source: gallery or camera
    final source = await _showImageSourceDialog();
    if (source == null) return;

    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1920,
      maxHeight: 1920,
    );
    if (picked == null) return;

    await controller.sendImageMessage(File(picked.path));
  }

  Future<ImageSource?> _showImageSourceDialog() async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: const Text('Take a Photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Voice Note
  // ---------------------------------------------------------------------------

  void _openVoiceRecordingSheet(ChatController controller) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _VoiceRecordingSheet(
        onSend: (File audioFile, int durationSeconds) async {
          Navigator.pop(ctx);
          await controller.sendVoiceMessage(audioFile, durationSeconds: durationSeconds);
        },
        onCancel: () => Navigator.pop(ctx),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Location
  // ---------------------------------------------------------------------------

  Future<void> _sendCurrentLocation(ChatController controller) async {
    // Check/request permission
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission denied')),
        );
      }
      return;
    }

    setState(() => _isLocating = true);
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      await controller.sendLocationMessage(pos.latitude, pos.longitude);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not get location: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _showMessageContextMenu({
    required BuildContext context,
    required MessageEntity msg,
    required ChatMessagePayload payload,
    required bool isSelf,
    required ChatController controller,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final text = payload.text ?? '';

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
              if (text.isNotEmpty)
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
                    _replyingToText = text.isNotEmpty ? text : '[${payload.type.name} attachment]';
                  });
                },
              ),
              if (isSelf)
                ListTile(
                  leading: const Icon(Icons.delete_forever_rounded, color: Colors.red),
                  title: const Text('Delete for Everyone', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Remove for both participants and delete server media'),
                  onTap: () {
                    Navigator.pop(context);
                    controller.deleteMessageForEveryone(msg);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Message deleted for everyone')),
                    );
                  },
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Colors.orange),
                title: const Text('Delete for Me', style: TextStyle(color: Colors.orange)),
                subtitle: const Text('Remove from this device only'),
                onTap: () {
                  Navigator.pop(context);
                  controller.deleteMessageForMe(msg);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Message deleted for you')),
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
    final sessionArgs = ChatSessionArgs(roomId: widget.roomId, peerId: widget.peerId, requestStatus: widget.initialStatus);
    final chatState = ref.watch(chatControllerProvider(sessionArgs));
    final controller = ref.read(chatControllerProvider(sessionArgs).notifier);
    final currentUserId = ref.watch(chatRepositoryProvider).currentUserId;
    final isAccepted = chatState.requestStatus == ChatRequestStatus.accepted;

    // Show upload errors as snackbars and auto-clear the error state
    ref.listen<ChatState>(chatControllerProvider(sessionArgs), (prev, next) {
      if (next.uploadError != null && next.uploadError != prev?.uploadError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.uploadError!),
            backgroundColor: Colors.red.shade700,
          ),
        );
        controller.clearUploadError();
      }
    });

    // Resolve peer display name from discovered nearby users to avoid exposing raw UUID
    final nearbyUsers = ref.watch(proximityUsersProvider);
    final peerUser = nearbyUsers.where((u) => u.userId == widget.peerId).firstOrNull;
    final peerDisplayName = (peerUser?.displayName != null && peerUser!.displayName!.isNotEmpty)
        ? peerUser.displayName!
        : (peerUser?.username.isNotEmpty == true
            ? peerUser!.username
            : 'Nearby Peer');

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: ClayColors.background,
        appBar: AppBar(
          backgroundColor: ClayColors.background,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: ClayColors.cardSurface,
                shape: BoxShape.circle,
                boxShadow: ClayShadows.button,
              ),
              child: Icon(Icons.arrow_back_ios_new_rounded, size: 14, color: ClayColors.textPrimary),
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: GestureDetector(
            onTap: () => _showPeerProfileModal(context, chatState.isRecipientOnline, peerDisplayName),
            child: Row(
              children: [
                Stack(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: ClayColors.cardSurface,
                        shape: BoxShape.circle,
                        boxShadow: ClayShadows.card,
                        border: Border.all(color: ClayColors.borderSubtle),
                      ),
                      child: Center(
                        child: Text(
                          peerDisplayName.isNotEmpty ? peerDisplayName[0].toUpperCase() : 'P',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: ClayColors.accent,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: chatState.isRecipientOnline ? const Color(0xFF10B981) : const Color(0xFF9CA3AF),
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      peerDisplayName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: ClayColors.textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Text(
                      chatState.isRecipientOnline ? 'Active nearby' : 'Offline',
                      style: TextStyle(fontSize: 11, color: ClayColors.textSecondary),
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
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: ClayColors.cardSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: ClayColors.borderSubtle),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.wifi_off_rounded, size: 14, color: ClayColors.textSecondary),
                    const SizedBox(width: 8),
                    Text(
                      'Peer offline • Messages will sync when reconnected',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ClayColors.textSecondary),
                    ),
                  ],
                ),
              ),

            // Request status banner (Pending or Denied)
            if (chatState.requestStatus == ChatRequestStatus.pending)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.hourglass_top_rounded, size: 14, color: Colors.amber.shade800),
                    const SizedBox(width: 8),
                    Text(
                      'Chat invitation pending recipient acceptance',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.amber.shade900),
                    ),
                  ],
                ),
              )
            else if (chatState.requestStatus == ChatRequestStatus.denied)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.block_rounded, size: 14, color: Color(0xFFDC2626)),
                    const SizedBox(width: 8),
                    const Text(
                      'Chat invitation was declined',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFDC2626)),
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
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: ClayShadows.card,
                            ),
                            child: const EasyChatLogoMark(size: 38),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Say Hello to $peerDisplayName',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: ClayColors.textPrimary,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Messages are private, secure, and ephemeral.',
                            style: TextStyle(fontSize: 13, color: ClayColors.textSecondary),
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
                        
                        // Decode / decrypt payload
                        ChatMessagePayload payload;
                        final rawString = utf8.decode(msg.encryptedPayload, allowMalformed: true);
                        if (!rawString.startsWith('E2EE:v2:') && !rawString.startsWith('E2EE:v1:')) {
                          payload = ChatMessagePayload.plainText('🔒 [Unauthenticated / Invalid Message]');
                        } else if (_decryptedPayloads.containsKey(msg.messageId)) {
                          payload = _decryptedPayloads[msg.messageId]!;
                        } else {
                          payload = ChatMessagePayload.plainText('🔒 Decrypting...');
                          controller.decryptPayload(msg).then((dec) {
                            if (mounted) {
                              setState(() {
                                _decryptedPayloads[msg.messageId] = dec;
                              });
                            }
                          });
                        }
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
                                  _replyingToText = payload.text ?? '[attachment]';
                                });
                                return false;
                              },
                              background: Container(
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.only(left: 20),
                                child: Icon(Icons.reply_rounded, color: ClayColors.accent),
                              ),
                              child: GestureDetector(
                                onLongPress: () => _showMessageContextMenu(
                                  context: context,
                                  msg: msg,
                                  payload: payload,
                                  isSelf: isSelf,
                                  controller: controller,
                                ),
                                child: _MessageBubble(
                                  key: ValueKey(msg.messageId),
                                  payload: payload,
                                  createdAt: msg.createdAt,
                                  isSelf: isSelf,
                                  isRead: isRead,
                                  peerDisplayName: peerDisplayName,
                                  roomId: widget.roomId,
                                  messageId: msg.messageId,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),

            // Typing indicator + attachment upload progress
            if (chatState.isUploading)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: ClayColors.accent,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Uploading attachment...',
                      style: TextStyle(fontSize: 12, color: ClayColors.textSecondary),
                    ),
                  ],
                ),
              )
            else if (chatState.isRecipientTyping)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: ClayColors.accentLight,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            peerDisplayName.isNotEmpty ? peerDisplayName[0].toUpperCase() : 'P',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: ClayColors.accent),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _TypingDotsIndicator(color: ClayColors.accent),
                      const SizedBox(width: 6),
                      Text(
                        '$peerDisplayName is typing...',
                        style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: ClayColors.accent),
                      ),
                    ],
                  ),
                ),
              ),

            // Swipe Reply Preview Header Bar
            if (_replyingToText != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: ClayColors.cardSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: ClayColors.borderSubtle),
                ),
                child: Row(
                  children: [
                    Icon(Icons.reply_rounded, size: 18, color: ClayColors.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Replying to: $_replyingToText',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: ClayColors.textSecondary),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => setState(() => _replyingToText = null),
                    ),
                  ],
                ),
              ),

            // Locating overlay indicator
            if (_isLocating)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: ClayColors.cardSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: ClayColors.borderSubtle),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: ClayColors.accent),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Getting your location...',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ClayColors.textSecondary),
                    ),
                  ],
                ),
              ),

            // Premium Tactile Clay Message input toolbar
            Padding(
              padding: const EdgeInsets.only(left: 12, right: 12, bottom: 16, top: 4),
              child: ClayCard(
                borderRadius: BorderRadius.circular(30),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.add_circle_outline_rounded,
                        color: isAccepted ? ClayColors.accent : ClayColors.textSecondary.withOpacity(0.38),
                      ),
                      onPressed: isAccepted ? () => _showAttachmentMenu(context, controller) : null,
                    ),
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        focusNode: _focusNode,
                        enabled: isAccepted,
                        onChanged: (text) {
                          if (isAccepted) {
                            _setTyping(text.isNotEmpty);
                          }
                        },
                        decoration: InputDecoration(
                          hintText: !isAccepted
                              ? (chatState.requestStatus == ChatRequestStatus.denied
                                  ? 'Chat request declined'
                                  : 'Waiting for acceptance...')
                              : 'Type a message...',
                          hintStyle: TextStyle(
                            fontSize: 14,
                            color: ClayColors.textSecondary.withOpacity(0.7),
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: isAccepted
                          ? () {
                              final text = _textController.text;
                              if (text.trim().isNotEmpty) {
                                controller.sendChatMessage(text);
                                _textController.clear();
                                _setTyping(false);
                                if (_replyingToText != null) {
                                  setState(() => _replyingToText = null);
                                }
                              }
                            }
                          : null,
                      child: Container(
                        width: 42,
                        height: 42,
                        margin: const EdgeInsets.only(right: 2),
                        decoration: BoxDecoration(
                          color: isAccepted ? ClayColors.accent : ClayColors.borderSubtle,
                          shape: BoxShape.circle,
                          boxShadow: isAccepted ? ClayShadows.button : null,
                        ),
                        child: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
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
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
              boxShadow: ClayShadows.card,
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ClayColors.textPrimary)),
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
            color: ClayColors.cardSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: ClayColors.borderSubtle),
          ),
          child: Text(
            dateStr,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ClayColors.textSecondary),
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
    return RepaintBoundary(
      child: AnimatedBuilder(
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
      ),
    );
  }
}

class _DecryptedImageWidget extends StatelessWidget {
  final ChatMessagePayload payload;
  final double width;
  final String? roomId;
  final String? messageId;

  const _DecryptedImageWidget({
    required this.payload,
    required this.width,
    this.roomId,
    this.messageId,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: MediaRepository().downloadAndDecryptMediaBytes(
        fileId: payload.mediaFileId!,
        mediaKey: payload.mediaKey!,
        mediaNonce: payload.mediaNonce!,
        cryptoService: CryptoService(),
        roomId: roomId,
        messageId: messageId,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            width: width,
            height: 160,
            color: ClayColors.cardSurface,
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Container(
            width: width,
            height: 160,
            color: ClayColors.cardSurface,
            child: const Center(
              child: Icon(Icons.broken_image_rounded, size: 40, color: Colors.grey),
            ),
          );
        }
        return Image.memory(
          snapshot.data!,
          fit: BoxFit.cover,
          width: width,
        );
      },
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessagePayload payload;
  final DateTime createdAt;
  final bool isSelf;
  final bool isRead;
  final String peerDisplayName;
  final String? roomId;
  final String? messageId;

  const _MessageBubble({
    super.key,
    required this.payload,
    required this.createdAt,
    required this.isSelf,
    required this.isRead,
    required this.peerDisplayName,
    this.roomId,
    this.messageId,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isSelf ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isSelf) ...[
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: ClayColors.cardSurface,
                shape: BoxShape.circle,
                border: Border.all(color: ClayColors.borderSubtle),
              ),
              child: Center(
                child: Text(
                  peerDisplayName.isNotEmpty ? peerDisplayName[0].toUpperCase() : 'P',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: ClayColors.accent),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
            decoration: BoxDecoration(
              color: isSelf ? ClayColors.accent : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: Radius.circular(isSelf ? 20 : 4),
                bottomRight: Radius.circular(isSelf ? 4 : 20),
              ),
              boxShadow: isSelf ? ClayShadows.button : ClayShadows.card,
            ),
            child: _buildContent(context),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    switch (payload.type) {
      case MessageType.image:
        return _buildImageContent(context);
      case MessageType.voice:
        return _buildVoiceContent(context);
      case MessageType.location:
        return _buildLocationContent(context);
      case MessageType.text:
        return _buildTextContent(context);
    }
  }

  Widget _buildTextContent(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Column(
        crossAxisAlignment: isSelf ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(
            payload.text ?? '',
            style: TextStyle(
              fontSize: 15,
              color: isSelf ? Colors.white : ClayColors.textPrimary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 4),
          _buildTimestampRow(),
        ],
      ),
    );
  }

  Widget _buildImageContent(BuildContext context) {
    final width = MediaQuery.of(context).size.width * 0.68;
    final isEncrypted = payload.mediaFileId != null &&
        payload.mediaFileId!.isNotEmpty &&
        payload.mediaKey != null &&
        payload.mediaNonce != null;
    final url = payload.resolvedMediaUrl ?? payload.mediaUrl ?? '';

    return ClipRRect(
      borderRadius: BorderRadius.only(
        topLeft: const Radius.circular(20),
        topRight: const Radius.circular(20),
        bottomLeft: Radius.circular(isSelf ? 20 : 4),
        bottomRight: Radius.circular(isSelf ? 4 : 20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isEncrypted)
            _DecryptedImageWidget(
              payload: payload,
              width: width,
              roomId: roomId,
              messageId: messageId,
            )
          else if (url.isNotEmpty)
            Image.network(
              url,
              fit: BoxFit.cover,
              width: width,
              errorBuilder: (_, __, ___) => Container(
                width: width,
                height: 160,
                color: ClayColors.cardSurface,
                child: const Center(
                  child: Icon(Icons.broken_image_rounded, size: 40, color: Colors.grey),
                ),
              ),
              loadingBuilder: (_, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(
                  width: width,
                  height: 160,
                  color: ClayColors.cardSurface,
                  child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                );
              },
            )
          else
            Container(
              width: width,
              height: 160,
              color: ClayColors.cardSurface,
              child: const Center(
                child: Icon(Icons.image_rounded, size: 40, color: Colors.grey),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: _buildTimestampRow(),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceContent(BuildContext context) {
    return _VoiceBubbleContent(
      payload: payload,
      isSelf: isSelf,
      timestampRow: _buildTimestampRow(),
      roomId: roomId,
      messageId: messageId,
    );
  }

  Widget _buildLocationContent(BuildContext context) {
    final lat = payload.latitude?.toStringAsFixed(5) ?? '—';
    final lng = payload.longitude?.toStringAsFixed(5) ?? '—';
    final mapsUrl =
        'https://www.google.com/maps/search/?api=1&query=${payload.latitude},${payload.longitude}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: isSelf ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isSelf ? Colors.white24 : const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.location_on_rounded,
                  color: isSelf ? Colors.white : Colors.green.shade700,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Shared Location',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: isSelf ? Colors.white : ClayColors.textPrimary,
                    ),
                  ),
                  Text(
                    '$lat, $lng',
                    style: TextStyle(
                      fontSize: 11,
                      color: isSelf ? Colors.white70 : ClayColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () async {
              try {
                await AudioPlayerService.openMaps(mapsUrl);
              } catch (_) {
                await Clipboard.setData(ClipboardData(text: mapsUrl));
              }
            },
            child: Text(
              'Open in Maps →',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isSelf ? Colors.white : Colors.green.shade700,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
          const SizedBox(height: 4),
          _buildTimestampRow(),
        ],
      ),
    );
  }

  Widget _buildTimestampRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}',
          style: TextStyle(
            fontSize: 10,
            color: isSelf ? Colors.white.withOpacity(0.75) : ClayColors.textSecondary,
          ),
        ),
        if (isSelf) ...[
          const SizedBox(width: 4),
          Icon(
            isRead ? Icons.done_all_rounded : Icons.done_rounded,
            size: 14,
            color: Colors.white,
          ),
        ]
      ],
    );
  }
}

class _VoiceBubbleContent extends StatefulWidget {
  final ChatMessagePayload payload;
  final bool isSelf;
  final Widget timestampRow;
  final String? roomId;
  final String? messageId;

  const _VoiceBubbleContent({
    required this.payload,
    required this.isSelf,
    required this.timestampRow,
    this.roomId,
    this.messageId,
  });

  @override
  State<_VoiceBubbleContent> createState() => _VoiceBubbleContentState();
}

class _VoiceBubbleContentState extends State<_VoiceBubbleContent> {
  bool _isPlaying = false;
  bool _isLoading = false;

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await AudioPlayerService.stop();
      if (mounted) setState(() => _isPlaying = false);
      return;
    }

    setState(() => _isLoading = true);
    try {
      String playPath = '';
      if (widget.payload.mediaFileId != null &&
          widget.payload.mediaFileId!.isNotEmpty &&
          widget.payload.mediaKey != null &&
          widget.payload.mediaNonce != null) {
        final decFile = await MediaRepository().downloadAndDecryptMedia(
          fileId: widget.payload.mediaFileId!,
          mediaKey: widget.payload.mediaKey!,
          mediaNonce: widget.payload.mediaNonce!,
          cryptoService: CryptoService(),
          roomId: widget.roomId,
          messageId: widget.messageId,
        );
        playPath = decFile.path;
      } else {
        playPath = widget.payload.resolvedMediaUrl ?? widget.payload.mediaUrl ?? '';
      }

      if (playPath.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final success = await AudioPlayerService.play(playPath);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isPlaying = success;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final secs = widget.payload.durationSeconds ?? 0;
    final duration =
        '${(secs ~/ 60).toString().padLeft(2, '0')}:${(secs % 60).toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: widget.isSelf ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: _togglePlay,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: widget.isSelf ? Colors.white24 : ClayColors.accentLight,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: _isLoading
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                widget.isSelf ? Colors.white : ClayColors.accent,
                              ),
                            ),
                          )
                        : Icon(
                            _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: widget.isSelf ? Colors.white : ClayColors.accent,
                            size: 24,
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.graphic_eq_rounded,
                    color: widget.isSelf ? Colors.white70 : ClayColors.textSecondary,
                    size: 22,
                  ),
                  Text(
                    duration,
                    style: TextStyle(
                      fontSize: 11,
                      color: widget.isSelf ? Colors.white70 : ClayColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          widget.timestampRow,
        ],
      ),
    );
  }
}

// =============================================================================
// Voice Recording Sheet
// =============================================================================

class _VoiceRecordingSheet extends StatefulWidget {
  final Future<void> Function(File audioFile, int durationSeconds) onSend;
  final VoidCallback onCancel;

  const _VoiceRecordingSheet({required this.onSend, required this.onCancel});

  @override
  State<_VoiceRecordingSheet> createState() => _VoiceRecordingSheetState();
}

class _VoiceRecordingSheetState extends State<_VoiceRecordingSheet> {
  final Record _recorder = Record();
  bool _isRecording = false;
  bool _isSending = false;
  int _elapsedSeconds = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startRecording();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission denied')),
        );
        widget.onCancel();
      }
      return;
    }

    final dir = await _getTempDir();
    final path = '$dir/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      path: path,
      encoder: AudioEncoder.aacLc,
      bitRate: 64000,
      samplingRate: 44100,
    );

    setState(() {
      _isRecording = true;
      _elapsedSeconds = 0;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
  }

  Future<String> _getTempDir() async {
    // Use the system temp directory
    return Directory.systemTemp.path;
  }

  Future<void> _stopAndSend() async {
    _timer?.cancel();
    setState(() => _isSending = true);
    final path = await _recorder.stop();
    setState(() => _isRecording = false);

    if (path != null && path.isNotEmpty) {
      final file = File(path);
      if (await file.exists()) {
        await widget.onSend(file, _elapsedSeconds);
        return;
      }
    }
    // Recording failed or empty
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recording failed: no audio captured')),
      );
      widget.onCancel();
    }
  }

  Future<void> _cancel() async {
    _timer?.cancel();
    await _recorder.stop();
    widget.onCancel();
  }

  String get _formattedTime {
    final m = (_elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: ClayColors.borderSubtle,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isRecording ? Icons.mic_rounded : Icons.mic_off_rounded,
                color: Colors.redAccent,
                size: 36,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _isRecording ? 'Recording...' : 'Stopped',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: ClayColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _formattedTime,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: Colors.redAccent,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Cancel'),
                    onPressed: _isSending ? null : _cancel,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: ClayColors.borderSubtle),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: _isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send_rounded),
                    label: Text(_isSending ? 'Sending...' : 'Send'),
                    onPressed: _isSending || !_isRecording ? null : _stopAndSend,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ClayColors.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

