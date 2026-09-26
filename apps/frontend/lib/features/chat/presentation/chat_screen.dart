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
import '../../../core/theme/app_colors.dart';
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
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.border, width: 0.8),
                ),
                child: Center(
                  child: Text(
                    peerName.isNotEmpty ? peerName[0].toUpperCase() : 'P',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                peerName,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.2,
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
                      color: isOnline ? AppColors.success : AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isOnline ? 'Active nearby' : 'Offline',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ClayCard(
                padding: const EdgeInsets.all(16),
                borderRadius: BorderRadius.circular(12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: AppColors.surfaceVariant,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.shield_outlined, color: AppColors.icon, size: 18),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Private nearby chat',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Messages are ephemeral and private between you and this nearby peer.',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: AppColors.textSecondary,
                              height: 1.3,
                            ),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                  icon: Icons.image_outlined,
                  label: 'Image',
                  color: AppColors.primary,
                  onTap: () async {
                    Navigator.pop(ctx);
                    final source = await _showImageSourceDialog();
                    if (source != null) {
                      await _pickAndSendImage(controller, source: source);
                    }
                  },
                ),
                _AttachmentOption(
                  icon: Icons.mic_none_outlined,
                  label: 'Voice note',
                  color: AppColors.primary,
                  onTap: () {
                    Navigator.pop(ctx);
                    _openVoiceRecordingSheet(controller);
                  },
                ),
                _AttachmentOption(
                  icon: Icons.location_on_outlined,
                  label: 'Location',
                  color: AppColors.primary,
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

  Future<void> _pickAndSendImage(ChatController controller, {ImageSource source = ImageSource.gallery}) async {
    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1920,
      maxHeight: 1920,
    );
    if (picked == null || !mounted) return;

    final imageFile = File(picked.path);
    final confirmed = await _showImagePreviewDialog(imageFile);
    if (confirmed == true && mounted) {
      await controller.sendImageMessage(imageFile);
    }
  }

  Future<bool?> _showImagePreviewDialog(File imageFile) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border, width: 0.8),
        ),
        title: const Row(
          children: [
            Icon(Icons.photo_library_outlined, color: AppColors.primary, size: 20),
            SizedBox(width: 8),
            Text(
              'Preview image',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                constraints: const BoxConstraints(maxHeight: 260),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  border: Border.all(color: AppColors.border, width: 0.8),
                ),
                child: Image.file(
                  imageFile,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline_rounded, size: 12, color: AppColors.textSecondary),
                SizedBox(width: 4),
                Text(
                  'End-to-end encrypted before upload',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          ClayButton(
            label: 'Send',
            icon: Icons.send_rounded,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
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
              leading: const Icon(Icons.photo_library_outlined, color: AppColors.icon),
              title: const Text('Choose from gallery', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textPrimary)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined, color: AppColors.icon),
              title: const Text('Take a photo', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textPrimary)),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                  leading: const Icon(Icons.copy_rounded, color: AppColors.icon),
                  title: const Text('Copy text', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textPrimary)),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: text));
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Message copied to clipboard')),
                    );
                  },
                ),
              ListTile(
                leading: const Icon(Icons.reply_rounded, color: AppColors.primary),
                title: const Text('Reply', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _replyingToText = text.isNotEmpty ? text : '[${payload.type.name} attachment]';
                  });
                },
              ),
              if (isSelf)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                  title: const Text('Delete for everyone', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w500, fontSize: 14)),
                  subtitle: const Text('Remove for both participants and delete server media', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  onTap: () {
                    Navigator.pop(context);
                    controller.deleteMessageForEveryone(msg);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Message deleted for everyone')),
                    );
                  },
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: AppColors.icon),
                title: const Text('Delete for me', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w400, fontSize: 14)),
                subtitle: const Text('Remove from this device only', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
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
    final distanceText = (peerUser != null && peerUser.distanceMeters > 0)
        ? ' • ${peerUser.formattedDistance}'
        : '';
    final statusText = chatState.isRecipientOnline
        ? 'Online now$distanceText'
        : 'Offline';

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          scrolledUnderElevation: 0,
          leadingWidth: 54,
          leading: Center(
            child: ClayCircleButton(
              icon: Icons.arrow_back_ios_new_rounded,
              onPressed: () => Navigator.of(context).pop(),
              size: 38,
              iconSize: 15,
            ),
          ),
          titleSpacing: 4,
          title: GestureDetector(
            onTap: () => _showPeerProfileModal(context, chatState.isRecipientOnline, peerDisplayName),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border, width: 0.8),
                      ),
                      child: Center(
                        child: Text(
                          peerDisplayName.isNotEmpty ? peerDisplayName[0].toUpperCase() : 'P',
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 15,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    if (chatState.isRecipientOnline)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.success,
                            border: Border.all(color: AppColors.background, width: 1.5),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        peerDisplayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        statusText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                          color: chatState.isRecipientOnline ? AppColors.textSecondary : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            ClayCircleButton(
              icon: Icons.phone_outlined,
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Voice calls coming soon')),
                );
              },
              size: 38,
              iconSize: 18,
            ),
            const SizedBox(width: 8),
            ClayCircleButton(
              icon: Icons.more_horiz_rounded,
              onPressed: () => _showPeerProfileModal(context, chatState.isRecipientOnline, peerDisplayName),
              size: 38,
              iconSize: 18,
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: Column(
          children: [
            // Connection status/offline banner
            if (!chatState.isRecipientOnline)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border, width: 0.8),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.wifi_off_outlined, size: 14, color: AppColors.icon),
                    SizedBox(width: 8),
                    Text(
                      'Peer offline • Messages will sync when reconnected',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.textSecondary),
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
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border, width: 0.8),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.hourglass_top_rounded, size: 14, color: AppColors.icon),
                    SizedBox(width: 8),
                    Text(
                      'Chat invitation pending recipient acceptance',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              )
            else if (chatState.requestStatus == ChatRequestStatus.denied)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border, width: 0.8),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.block_outlined, size: 14, color: AppColors.icon),
                    SizedBox(width: 8),
                    Text(
                      'Chat invitation was declined',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.textSecondary),
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
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.border, width: 0.8),
                            ),
                            child: const EasyChatLogoMark(size: 38),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Say hello to $peerDisplayName',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Messages are private, secure, and ephemeral.',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: AppColors.textSecondary),
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

                        // Consecutive message cluster detection:
                        // Show ONE timestamp below the message cluster (on the last message in cluster).
                        final isLastInCluster = (index == chatState.messages.length - 1) ||
                            (chatState.messages[index + 1].senderId != msg.senderId) ||
                            (chatState.messages[index + 1].createdAt.day != msg.createdAt.day ||
                             chatState.messages[index + 1].createdAt.month != msg.createdAt.month ||
                             chatState.messages[index + 1].createdAt.year != msg.createdAt.year);

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
                                child: const Icon(Icons.reply_rounded, color: AppColors.primary),
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
                                  showTimestamp: isLastInCluster,
                                  isLastInCluster: isLastInCluster,
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
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Uploading attachment...',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.textSecondary),
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
                          color: AppColors.surfaceVariant,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.border, width: 0.8),
                        ),
                        child: Center(
                          child: Text(
                            peerDisplayName.isNotEmpty ? peerDisplayName[0].toUpperCase() : 'P',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const _TypingDotsIndicator(color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Text(
                        '$peerDisplayName is typing...',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.textSecondary),
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
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border, width: 0.8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.reply_rounded, size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Replying to: $_replyingToText',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.textSecondary),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.icon),
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
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border, width: 0.8),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Getting your location...',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),

            // Tactile Composer: [ Attachment ] [ Write a message... ] [ Voice ] [ Blue Send ]
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 16),
              child: Row(
                children: [
                  // 1. Attachment Button: opens device native photo/gallery picker on tap, long press for menu
                  ClayCircleButton(
                    icon: Icons.attach_file_rounded,
                    tooltip: 'Attach photo or location',
                    onPressed: isAccepted ? () => _pickAndSendImage(controller) : null,
                    onLongPress: isAccepted ? () => _showAttachmentMenu(context, controller) : null,
                    size: 40,
                    iconSize: 20,
                    iconColor: isAccepted ? AppColors.icon : AppColors.disabled,
                  ),
                  const SizedBox(width: 8),

                  // 2. Input field: soft rounded white surface with "Write a message..." placeholder
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: AppColors.border, width: 0.8),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x061F2328),
                            blurRadius: 6,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _textController,
                        focusNode: _focusNode,
                        enabled: isAccepted,
                        onChanged: (text) {
                          if (isAccepted) {
                            _setTyping(text.isNotEmpty);
                          }
                        },
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: AppColors.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: !isAccepted
                              ? (chatState.requestStatus == ChatRequestStatus.denied
                                  ? 'Chat request declined'
                                  : 'Waiting for acceptance...')
                              : 'Write a message...',
                          hintStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: AppColors.textMuted,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 3. Voice Button: direct access to voice note recording
                  ClayCircleButton(
                    icon: Icons.mic_none_rounded,
                    tooltip: 'Record voice message',
                    onPressed: isAccepted ? () => _openVoiceRecordingSheet(controller) : null,
                    size: 40,
                    iconSize: 20,
                    iconColor: isAccepted ? AppColors.icon : AppColors.disabled,
                  ),
                  const SizedBox(width: 8),

                  // 4. Send: circular #3B6FE0 button, white send icon
                  ClayCircleButton(
                    icon: Icons.send_rounded,
                    tooltip: 'Send message',
                    onPressed: isAccepted
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
                    backgroundColor: isAccepted ? AppColors.primary : AppColors.disabled,
                    iconColor: Colors.white,
                    size: 40,
                    iconSize: 18,
                    border: Border.all(color: Colors.transparent),
                    shadows: isAccepted
                        ? const [
                            BoxShadow(
                              color: Color(0x333B6FE0),
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ]
                        : null,
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
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border, width: 0.8),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.textPrimary)),
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border, width: 0.8),
          ),
          child: Text(
            dateStr,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
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

class DecryptedImageWidget extends ConsumerStatefulWidget {
  final ChatMessagePayload payload;
  final double width;
  final String? roomId;
  final String? messageId;

  const DecryptedImageWidget({
    super.key,
    required this.payload,
    required this.width,
    this.roomId,
    this.messageId,
  });

  @override
  ConsumerState<DecryptedImageWidget> createState() => _DecryptedImageWidgetState();
}

typedef _DecryptedImageWidget = DecryptedImageWidget;

class _DecryptedImageWidgetState extends ConsumerState<DecryptedImageWidget> {
  Future<Uint8List>? _mediaFuture;

  @override
  void initState() {
    super.initState();
    _initFuture();
  }

  void _initFuture() {
    final fileId = widget.payload.mediaFileId;
    final mediaKey = widget.payload.mediaKey;
    final mediaNonce = widget.payload.mediaNonce;
    if (fileId == null || mediaKey == null || mediaNonce == null) {
      _mediaFuture = null;
      return;
    }
    final mediaRepo = ref.read(mediaRepositoryProvider);
    _mediaFuture = mediaRepo.downloadAndDecryptMediaBytes(
      fileId: fileId,
      mediaKey: mediaKey,
      mediaNonce: mediaNonce,
      cryptoService: CryptoService(),
      roomId: widget.roomId,
      messageId: widget.messageId,
    );
  }

  @override
  void didUpdateWidget(covariant DecryptedImageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.payload.mediaFileId != widget.payload.mediaFileId ||
        oldWidget.payload.mediaKey != widget.payload.mediaKey ||
        oldWidget.payload.mediaNonce != widget.payload.mediaNonce ||
        oldWidget.roomId != widget.roomId ||
        oldWidget.messageId != widget.messageId) {
      setState(() {
        _initFuture();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_mediaFuture == null) {
      return Container(
        width: widget.width,
        height: 160,
        color: AppColors.surfaceVariant,
        child: const Center(
          child: Icon(Icons.broken_image_rounded, size: 40, color: AppColors.icon),
        ),
      );
    }

    final mediaRepo = ref.watch(mediaRepositoryProvider);
    final fileId = widget.payload.mediaFileId;
    final cachedBytes = (fileId != null && fileId.isNotEmpty)
        ? mediaRepo.getCachedDecryptedBytes(fileId)
        : null;

    return FutureBuilder<Uint8List>(
      future: _mediaFuture,
      initialData: cachedBytes,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Container(
            width: widget.width,
            height: 160,
            color: AppColors.surfaceVariant,
            child: const Center(
              child: Icon(Icons.broken_image_rounded, size: 40, color: AppColors.icon),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return Container(
            width: widget.width,
            height: 160,
            color: AppColors.surfaceVariant,
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
          );
        }
        if (snapshot.hasData) {
          return Image.memory(
            snapshot.data!,
            fit: BoxFit.cover,
            width: widget.width,
          );
        }
        return Container(
          width: widget.width,
          height: 160,
          color: AppColors.surfaceVariant,
          child: const Center(
            child: Icon(Icons.broken_image_rounded, size: 40, color: AppColors.icon),
          ),
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
  final bool showTimestamp;
  final bool isLastInCluster;
  final String peerDisplayName;
  final String? roomId;
  final String? messageId;

  const _MessageBubble({
    super.key,
    required this.payload,
    required this.createdAt,
    required this.isSelf,
    required this.isRead,
    this.showTimestamp = true,
    this.isLastInCluster = true,
    required this.peerDisplayName,
    this.roomId,
    this.messageId,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: 2,
        bottom: isLastInCluster ? 8 : 2,
      ),
      child: Row(
        mainAxisAlignment: isSelf ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isSelf) ...[
            SizedBox(
              width: 28,
              child: isLastInCluster
                  ? Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border, width: 0.8),
                      ),
                      child: Center(
                        child: Text(
                          peerDisplayName.isNotEmpty ? peerDisplayName[0].toUpperCase() : 'P',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    )
                  : const SizedBox(width: 28),
            ),
            const SizedBox(width: 8),
          ],
          Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
            decoration: BoxDecoration(
              color: isSelf ? AppColors.primary : AppColors.surface,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(isSelf ? 18 : 4),
                bottomRight: Radius.circular(isSelf ? 4 : 18),
              ),
              border: isSelf ? null : Border.all(color: AppColors.border, width: 0.8),
              boxShadow: isSelf
                  ? null
                  : const [
                      BoxShadow(
                        color: Color(0x061F2328),
                        blurRadius: 4,
                        offset: Offset(0, 1),
                      ),
                    ],
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: isSelf ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(
            payload.text ?? '',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: isSelf ? AppColors.textOnPrimary : AppColors.textPrimary,
              height: 1.35,
            ),
          ),
          if (showTimestamp) ...[
            const SizedBox(height: 3),
            _buildTimestampRow(),
          ],
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
        topLeft: const Radius.circular(16),
        topRight: const Radius.circular(16),
        bottomLeft: Radius.circular(isSelf ? 16 : 4),
        bottomRight: Radius.circular(isSelf ? 4 : 16),
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
                color: AppColors.surfaceVariant,
                child: const Center(
                  child: Icon(Icons.broken_image_rounded, size: 40, color: AppColors.icon),
                ),
              ),
              loadingBuilder: (_, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(
                  width: width,
                  height: 160,
                  color: AppColors.surfaceVariant,
                  child: const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
                );
              },
            )
          else
            Container(
              width: width,
              height: 160,
              color: AppColors.surfaceVariant,
              child: const Center(
                child: Icon(Icons.image_outlined, size: 40, color: AppColors.icon),
              ),
            ),
          if (showTimestamp)
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
      timestampRow: showTimestamp ? _buildTimestampRow() : const SizedBox.shrink(),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: isSelf ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isSelf ? Colors.white.withOpacity(0.18) : AppColors.surfaceVariant,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.location_on_outlined,
                  color: isSelf ? Colors.white : AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Shared location',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                      color: isSelf ? Colors.white : AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    '$lat, $lng',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: isSelf ? Colors.white70 : AppColors.textSecondary,
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
              'Open in maps →',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isSelf ? Colors.white : AppColors.primary,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
          if (showTimestamp) ...[
            const SizedBox(height: 4),
            _buildTimestampRow(),
          ],
        ],
      ),
    );
  }

  Widget _buildTimestampRow() {
    if (!showTimestamp) return const SizedBox.shrink();
    final hour12 = createdAt.hour == 0 ? 12 : (createdAt.hour > 12 ? createdAt.hour - 12 : createdAt.hour);
    final period = createdAt.hour >= 12 ? 'PM' : 'AM';
    final timeStr = '$hour12:${createdAt.minute.toString().padLeft(2, '0')} $period';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          timeStr,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w400,
            color: isSelf ? Colors.white.withOpacity(0.75) : AppColors.textSecondary,
          ),
        ),
        if (isSelf) ...[
          const SizedBox(width: 4),
          Icon(
            isRead ? Icons.done_all_rounded : Icons.done_rounded,
            size: 13,
            color: Colors.white.withOpacity(0.85),
          ),
        ]
      ],
    );
  }
}

class _AudioWaveformVisualizer extends StatelessWidget {
  final Color color;
  final bool isPlaying;

  const _AudioWaveformVisualizer({
    required this.color,
    this.isPlaying = false,
  });

  static const List<double> _waveformHeights = [
    8, 14, 22, 12, 18, 26, 16, 24, 10, 18, 22, 14, 20, 10, 16, 24, 18, 12, 8
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(_waveformHeights.length, (index) {
          final barH = _waveformHeights[index];
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            width: 2.5,
            height: barH,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(1.5),
            ),
          );
        }),
      ),
    );
  }
}

class _VoiceBubbleContent extends ConsumerStatefulWidget {
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
  ConsumerState<_VoiceBubbleContent> createState() => _VoiceBubbleContentState();
}

class _VoiceBubbleContentState extends ConsumerState<_VoiceBubbleContent> {
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
        final mediaRepo = ref.read(mediaRepositoryProvider);
        final decFile = await mediaRepo.downloadAndDecryptMedia(
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

    final playBtnBg = widget.isSelf ? Colors.white : AppColors.primary;
    final playBtnFg = widget.isSelf ? AppColors.primary : Colors.white;
    final waveColor = widget.isSelf ? Colors.white.withOpacity(0.85) : AppColors.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: widget.isSelf ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: _togglePlay,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: playBtnBg,
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x141F2328),
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: _isLoading
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(playBtnFg),
                            ),
                          )
                        : Icon(
                            _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: playBtnFg,
                            size: 22,
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _AudioWaveformVisualizer(
                color: waveColor,
                isPlaying: _isPlaying,
              ),
              const SizedBox(width: 10),
              Text(
                duration,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: widget.isSelf ? Colors.white.withOpacity(0.85) : AppColors.textSecondary,
                ),
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
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.mic_rounded,
                color: AppColors.primary,
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _isRecording ? 'Recording...' : 'Stopped',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _formattedTime,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w500,
                color: AppColors.primary,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Cancel'),
                    onPressed: _isSending ? null : _cancel,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: AppColors.border, width: 0.8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      foregroundColor: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: _isSending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send_rounded, size: 18),
                    label: Text(_isSending ? 'Sending...' : 'Send'),
                    onPressed: _isSending || !_isRecording ? null : _stopAndSend,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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

