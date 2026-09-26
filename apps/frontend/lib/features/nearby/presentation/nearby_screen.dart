import 'dart:async';
import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:dio/dio.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/utils/battery_optimizer.dart';
import '../../../core/services/location_service.dart';
import '../../auth/data/auth_repository.dart';
import '../../chat/presentation/chat_controller.dart';
import '../../chat/domain/chat_request.dart';
import '../data/nearby_repository.dart';
import '../domain/proximity_user.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/clay_design_system.dart';
import '../../../main.dart';

final batteryStateProvider = StateProvider<ActivityState>((ref) => ActivityState.stationary);
final gpsSettingsProvider = StateProvider<String>((ref) => 'GPS Active (2m filter)');
final bleDutyCycleProvider = StateProvider<String>((ref) => 'BLE Duty Cycle: Active');

class NearbyScreen extends ConsumerStatefulWidget {
  const NearbyScreen({super.key});

  @override
  ConsumerState<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends ConsumerState<NearbyScreen> with SingleTickerProviderStateMixin {
  StreamSubscription<Position>? _positionSub;
  StreamSubscription<Map<String, dynamic>>? _profileUpdateSub;
  StreamSubscription<ChatRequest>? _chatRequestSub;
  Position? _currentPosition;
  bool _isInitializing = true;
  bool _locationUnavailable = false;
  String _locationErrorMessage = '';
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  List<ChatRequest> _incomingRequests = [];
  final Map<String, ChatRequest> _peerRequestStatuses = {};
  final Set<String> _processingRequestIds = {};
  String? _myUserId;

  Timer? _heartbeatTimer;
  late AnimationController _radarAnimationController;

  @override
  void initState() {
    super.initState();
    _radarAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _initializeLocationAndDiscovery();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final chatRepo = ref.read(chatRepositoryProvider);
      chatRepo.ensureConnected();

      final authRepo = ref.read(authRepositoryProvider);
      _myUserId = await authRepo.getUserId();

      // Listen for real-time chat requests
      _chatRequestSub?.cancel();
      _chatRequestSub = chatRepo.chatRequests.listen((req) {
        if (!mounted) return;
        setState(() {
          if (req.status == ChatRequestStatus.pending) {
            if (req.recipientId == _myUserId) {
              _incomingRequests.removeWhere((r) => r.id == req.id);
              _incomingRequests.insert(0, req);
              _peerRequestStatuses[req.senderId] = req;
            } else if (req.senderId == _myUserId) {
              _peerRequestStatuses[req.recipientId] = req;
            }
          } else if (req.status == ChatRequestStatus.accepted || req.status == ChatRequestStatus.denied) {
            _incomingRequests.removeWhere((r) => r.id == req.id);
            _peerRequestStatuses[req.senderId] = req;
            _peerRequestStatuses[req.recipientId] = req;
          }
        });
      });

      await _fetchPendingRequests();

      _profileUpdateSub?.cancel();
      _profileUpdateSub = chatRepo.profileUpdates.listen((event) {
        if (!mounted) return;
        final userId = event['user_id'] as String?;
        final displayName = event['display_name'] as String?;
        final avatarUrl = event['avatar_url'] as String?;
        final bio = event['bio'] as String?;
        if (userId != null && userId.isNotEmpty) {
          ref.read(proximityUsersProvider.notifier).update((users) {
            return users.map((u) {
              if (u.userId == userId) {
                final pseudonym = u.username;
                final nameToUse = (displayName != null && displayName.isNotEmpty) ? displayName : pseudonym;
                return u.copyWith(
                  username: nameToUse,
                  displayName: displayName,
                  avatarUrl: avatarUrl,
                  bio: bio,
                );
              }
              return u;
            }).toList();
          });
        }
      });
    });
  }

  Future<void> _initializeLocationAndDiscovery() async {
    if (!mounted) return;
    setState(() {
      _isInitializing = true;
      _locationUnavailable = false;
      _locationErrorMessage = '';
    });

    final locationService = ref.read(locationServiceProvider);
    final hasPermission = await locationService.checkAndRequestPermission();

    if (hasPermission) {
      await _fetchNearbyUsers();

      // Listen to continuous position updates
      _positionSub?.cancel();
      _positionSub = locationService.getPositionStream().listen(
        (pos) {
          if (mounted) {
            setState(() {
              _currentPosition = pos;
              _locationUnavailable = false;
              _locationErrorMessage = '';
            });
          }
          _fetchNearbyUsers(pos.latitude, pos.longitude, pos.accuracy);
        },
        onError: (err) {
          dev.log('[NearbyScreen] Position stream error: $err', name: 'Location');
        },
      );

      // Periodic 15s heartbeat timer to maintain active Redis location TTL for stationary devices
      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        if (mounted) {
          _fetchNearbyUsers();
        }
      });
    } else {
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _locationUnavailable = true;
          _locationErrorMessage = 'Location permissions or services are disabled. Please grant location access.';
        });
      }
    }
  }

  Future<void> _fetchNearbyUsers([double? lat, double? lng, double? accuracy]) async {
    double? useLat = lat ?? _currentPosition?.latitude;
    double? useLng = lng ?? _currentPosition?.longitude;
    double? useAccuracy = accuracy ?? _currentPosition?.accuracy;

    if (useLat == null || useLng == null) {
      try {
        final serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          if (mounted) {
            setState(() {
              _locationUnavailable = true;
              _locationErrorMessage = 'Location services (GPS) are disabled. Please turn on GPS.';
              _isInitializing = false;
            });
          }
          return;
        }

        final permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          if (mounted) {
            setState(() {
              _locationUnavailable = true;
              _locationErrorMessage = 'Location permission is denied. Please grant location access.';
              _isInitializing = false;
            });
          }
          return;
        }

        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 8),
        );
        useLat = pos.latitude;
        useLng = pos.longitude;
        useAccuracy = pos.accuracy;
        if (mounted) {
          setState(() => _currentPosition = pos);
        }
      } catch (e) {
        try {
          final lastPos = await Geolocator.getLastKnownPosition();
          if (lastPos != null) {
            useLat = lastPos.latitude;
            useLng = lastPos.longitude;
            useAccuracy = lastPos.accuracy;
            if (mounted) {
              setState(() => _currentPosition = lastPos);
            }
          }
        } catch (_) {}
      }
    }

    // STRICT RULE: If GPS fails and no valid position exists, DO NOT send fake/fallback coordinates.
    if (useLat == null || useLng == null || (useLat == 0.0 && useLng == 0.0)) {
      if (mounted) {
        setState(() {
          _locationUnavailable = true;
          _locationErrorMessage = 'Location unavailable. Searching for GPS fix...';
          _isInitializing = false;
        });
      }
      return;
    }

    // Valid GPS coordinates acquired
    if (mounted && _locationUnavailable) {
      setState(() {
        _locationUnavailable = false;
        _locationErrorMessage = '';
      });
    }

    final nearbyRepo = ref.read(nearbyRepositoryProvider);
    await nearbyRepo.sendLocationHeartbeat(useLat, useLng, accuracy: useAccuracy);
    final users = await nearbyRepo.fetchNearbyUsers(latitude: useLat, longitude: useLng, accuracy: useAccuracy);

    if (mounted) {
      ref.read(proximityUsersProvider.notifier).state = users;
      if (_isInitializing) {
        setState(() => _isInitializing = false);
      }
      _fetchRequestStatusesForPeers(users);
    }
  }

  Future<void> _fetchPendingRequests() async {
    try {
      final chatRepo = ref.read(chatRepositoryProvider);
      final requests = await chatRepo.getPendingRequests();
      if (mounted) {
        setState(() {
          _incomingRequests = requests;
          for (final req in requests) {
            _peerRequestStatuses[req.senderId] = req;
          }
        });
      }
    } catch (e) {
      dev.log('Failed to fetch pending requests: $e');
    }
  }

  Future<void> _fetchRequestStatusesForPeers(List<ProximityUser> users) async {
    final chatRepo = ref.read(chatRepositoryProvider);
    for (final user in users) {
      try {
        final req = await chatRepo.getRequestStatus(user.userId);
        if (req != null && mounted) {
          setState(() {
            _peerRequestStatuses[user.userId] = req;
          });
        }
      } catch (_) {}
    }
  }

  Future<void> _sendChatRequest(ProximityUser peer) async {
    final nameToDisplay = peer.displayName?.isNotEmpty == true ? peer.displayName! : peer.username;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send Chat Request'),
        content: Text('Send a chat request to $nameToDisplay? Once accepted, you can start messaging.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send Request'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _processingRequestIds.add(peer.userId);
    });

    try {
      final chatRepo = ref.read(chatRepositoryProvider);
      final req = await chatRepo.sendChatRequest(peer.userId);
      if (mounted) {
        setState(() {
          _peerRequestStatuses[peer.userId] = req;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Chat request sent to $nameToDisplay!'),
            backgroundColor: Colors.indigo.shade800,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        String msg = e.toString();
        if (e is DioException && e.response?.data is Map) {
          final data = e.response!.data as Map;
          if (data['message'] != null) {
            msg = data['message'].toString();
          }
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _processingRequestIds.remove(peer.userId);
        });
      }
    }
  }

  Future<void> _acceptRequest(ChatRequest req) async {
    if (_processingRequestIds.contains(req.id)) return;
    setState(() => _processingRequestIds.add(req.id));

    try {
      final chatRepo = ref.read(chatRepositoryProvider);
      final updated = await chatRepo.acceptChatRequest(req.id);
      if (mounted) {
        setState(() {
          _incomingRequests.removeWhere((r) => r.id == req.id);
          _peerRequestStatuses[req.senderId] = updated;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Chat request accepted! Room is now active.'),
            backgroundColor: Colors.teal.shade800,
            action: SnackBarAction(
              label: 'Open Chat',
              textColor: Colors.amber,
              onPressed: () {
                if (updated.roomId != null && updated.roomId!.isNotEmpty) {
                  context.push('/chat/${updated.roomId}?peerId=${req.senderId}&status=ACCEPTED');
                }
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        String msg = e.toString();
        if (e is DioException && e.response?.data is Map) {
          final data = e.response!.data as Map;
          if (data['message'] != null) {
            msg = data['message'].toString();
          }
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _processingRequestIds.remove(req.id));
      }
    }
  }

  Future<void> _denyRequest(ChatRequest req) async {
    if (_processingRequestIds.contains(req.id)) return;
    setState(() => _processingRequestIds.add(req.id));

    try {
      final chatRepo = ref.read(chatRepositoryProvider);
      final updated = await chatRepo.denyChatRequest(req.id);
      if (mounted) {
        setState(() {
          _incomingRequests.removeWhere((r) => r.id == req.id);
          _peerRequestStatuses[req.senderId] = updated;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chat request denied.'),
            backgroundColor: Colors.grey,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to deny: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _processingRequestIds.remove(req.id));
      }
    }
  }

  Future<void> _startChatWithUser(ProximityUser peer) async {
    final authRepo = ref.read(authRepositoryProvider);
    final myUserId = await authRepo.getUserId();

    if (myUserId == null || myUserId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please log in to start a chat session.')),
        );
      }
      return;
    }

    // Clear unread count for this peer upon opening chat
    ref.read(unreadCountsProvider.notifier).update((state) {
      final map = Map<String, int>.from(state);
      map.remove(peer.userId);
      return map;
    });

    final currentRequest = _peerRequestStatuses[peer.userId];
    if (currentRequest != null && currentRequest.status == ChatRequestStatus.accepted && currentRequest.roomId != null) {
      if (!mounted) return;
      context.push('/chat/${currentRequest.roomId}?peerId=${peer.userId}&status=ACCEPTED');
      return;
    }

    try {
      final dioClient = ref.read(dioClientProvider);
      final response = await dioClient.dio.post(
        '/chat/rooms',
        data: {
          'userA': myUserId,
          'userB': peer.userId,
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        final roomId = response.data['roomId'] as String;
        if (mounted) {
          context.push('/chat/$roomId?peerId=${peer.userId}&status=ACCEPTED');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open chat room: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _positionSub?.cancel();
    _profileUpdateSub?.cancel();
    _chatRequestSub?.cancel();
    _heartbeatTimer?.cancel();
    _radarAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(proximityUsersProvider);
    final filteredUsers = _searchQuery.isEmpty
        ? users
        : users.where((u) {
            final q = _searchQuery.toLowerCase();
            final nameMatch = (u.displayName ?? u.username).toLowerCase().contains(q);
            final bioMatch = (u.bio ?? '').toLowerCase().contains(q);
            final interestMatch = u.interests?.any((i) => i.toLowerCase().contains(q)) ?? false;
            return nameMatch || bioMatch || interestMatch;
          }).toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        title: const Row(
          children: [
            EasyChatLogoMark(size: 26),
            SizedBox(width: 10),
            Text(
              'Easy chat',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 18,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
        actions: [
          ClayCircleButton(
            icon: Icons.sync_rounded,
            size: 36,
            iconSize: 18,
            iconColor: AppColors.icon,
            tooltip: 'Refresh',
            onPressed: () => _initializeLocationAndDiscovery(),
          ),
          const SizedBox(width: 8),
          ClayCircleButton(
            icon: Icons.person_outline_rounded,
            size: 36,
            iconSize: 18,
            iconColor: AppColors.icon,
            tooltip: 'My profile',
            onPressed: () => context.push('/profile'),
          ),
          const SizedBox(width: 14),
        ],
      ),
      backgroundColor: AppColors.background,
      bottomNavigationBar: ClayBottomNavigationBar(
        currentIndex: 0,
        onTap: (index) {
          if (index == 2) {
            context.push('/settings');
          }
        },
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: "Find people nearby" followed by rounded search field + filter
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Find people nearby',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 14),
                // Curved pill search field with integrated tactile filter button
                Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: AppColors.border, width: 0.8),
                    boxShadow: ClayShadows.card,
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 16),
                      const Icon(Icons.search_rounded, size: 20, color: AppColors.icon),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          onChanged: (val) {
                            setState(() {
                              _searchQuery = val.trim();
                            });
                          },
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: AppColors.textPrimary,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Search interests (e.g. coffee, hiking)',
                            hintStyle: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              color: AppColors.textMuted,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      if (_searchQuery.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.icon),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        ),
                      Padding(
                        padding: const EdgeInsets.only(right: 6.0),
                        child: ClayCircleButton(
                          icon: Icons.tune_rounded,
                          size: 40,
                          iconSize: 18,
                          iconColor: AppColors.icon,
                          tooltip: 'Filter interests',
                          onPressed: () => _initializeLocationAndDiscovery(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 4),

          Expanded(
            child: _isInitializing
                ? _LoadingRadarSkeleton(animationController: _radarAnimationController)
                : _locationUnavailable
                    ? _LocationDisabledCard(
                        errorMessage: _locationErrorMessage,
                        onRetry: _initializeLocationAndDiscovery,
                      )
                    : (users.isEmpty && _incomingRequests.isEmpty)
                        ? _EmptyNearbyState(onScan: _fetchNearbyUsers)
                        : ListView(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            children: [
                              if (_incomingRequests.isNotEmpty) ...[
                                _PendingRequestsSection(
                                  requests: _incomingRequests,
                                  processingIds: _processingRequestIds,
                                  onAccept: _acceptRequest,
                                  onDeny: _denyRequest,
                                ),
                                const SizedBox(height: 12),
                              ],
                              if (filteredUsers.isEmpty && _searchQuery.isNotEmpty)
                                Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 40),
                                    child: Column(
                                      children: [
                                        const Icon(Icons.search_off_rounded, size: 36, color: AppColors.icon),
                                        const SizedBox(height: 10),
                                        Text(
                                          'No people matching "$_searchQuery"',
                                          style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              else
                                ...filteredUsers.asMap().entries.map((entry) {
                                  final index = entry.key;
                                  final user = entry.value;
                                  final unreadCounts = ref.watch(unreadCountsProvider);
                                  final unreadCount = unreadCounts[user.userId] ?? 0;
                                  final req = _peerRequestStatuses[user.userId];
                                  final isProcessing = _processingRequestIds.contains(user.userId) ||
                                      (req != null && _processingRequestIds.contains(req.id));

                                  return _NearbyUserCard(
                                    key: ValueKey(user.userId),
                                    user: user,
                                    unreadCount: unreadCount,
                                    request: req,
                                    currentUserId: _myUserId,
                                    isProcessing: isProcessing,
                                    isNewHere: index == 0,
                                    onTapChat: () => _startChatWithUser(user),
                                    onSendRequest: () => _sendChatRequest(user),
                                    onAccept: req != null ? () => _acceptRequest(req) : null,
                                    onDeny: req != null ? () => _denyRequest(req) : null,
                                  );
                                }),
                            ],
                          ),
          ),
        ],
      ),
    );
  }
}


class _RadarRipplePainter extends CustomPainter {
  final double progress;
  final Color color;

  _RadarRipplePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    for (int i = 0; i < 2; i++) {
      final value = (progress + i * 0.5) % 1.0;
      final radius = maxRadius * value;
      final opacity = (1.0 - value).clamp(0.0, 1.0);

      final paint = Paint()
        ..color = color.withOpacity(opacity * 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarRipplePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _PendingRequestsSection extends StatelessWidget {
  final List<ChatRequest> requests;
  final Set<String> processingIds;
  final void Function(ChatRequest) onAccept;
  final void Function(ChatRequest) onDeny;

  const _PendingRequestsSection({
    required this.requests,
    required this.processingIds,
    required this.onAccept,
    required this.onDeny,
  });

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.month}/${dt.day}';
  }

  @override
  Widget build(BuildContext context) {
    return ClayCard(
      padding: const EdgeInsets.all(14.0),
      borderRadius: 12.0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: AppColors.surfaceVariant,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mark_chat_unread_rounded, color: AppColors.icon, size: 16),
              ),
              const SizedBox(width: 10),
              Text(
                'Chat requests (${requests.length})',
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...requests.map((req) {
            final isProcessing = processingIds.contains(req.id);
            final senderName = (req.senderDisplayName != null && req.senderDisplayName!.isNotEmpty)
                ? req.senderDisplayName!
                : (req.senderUsername != null && req.senderUsername!.isNotEmpty
                    ? req.senderUsername!
                    : 'Nearby Peer');
            final bio = req.senderBio ?? 'Wants to connect nearby';
            final timeStr = _formatTimestamp(req.createdAt);

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border, width: 0.8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: AppColors.surfaceVariant,
                        backgroundImage: req.senderAvatarUrl != null && req.senderAvatarUrl!.isNotEmpty
                            ? NetworkImage(req.senderAvatarUrl!) as ImageProvider
                            : null,
                        child: (req.senderAvatarUrl == null || req.senderAvatarUrl!.isEmpty)
                            ? Text(
                                senderName.isNotEmpty ? senderName[0].toUpperCase() : 'U',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textSecondary,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              senderName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              bio,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                                color: AppColors.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        timeStr,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (isProcessing)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                        )
                      else ...[
                        ClaySecondaryButton(
                          label: 'Deny',
                          icon: Icons.close_rounded,
                          onPressed: () => onDeny(req),
                        ),
                        const SizedBox(width: 8),
                        ClayButton(
                          label: 'Accept',
                          icon: Icons.check_rounded,
                          onPressed: () => onAccept(req),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _NearbyUserCard extends StatelessWidget {
  final ProximityUser user;
  final int unreadCount;
  final ChatRequest? request;
  final String? currentUserId;
  final bool isProcessing;
  final bool isNewHere;
  final VoidCallback onTapChat;
  final VoidCallback onSendRequest;
  final VoidCallback? onAccept;
  final VoidCallback? onDeny;

  const _NearbyUserCard({
    super.key,
    required this.user,
    required this.unreadCount,
    this.request,
    this.currentUserId,
    this.isProcessing = false,
    this.isNewHere = false,
    required this.onTapChat,
    required this.onSendRequest,
    this.onAccept,
    this.onDeny,
  });

  @override
  @override
  Widget build(BuildContext context) {
    final nameToDisplay = (user.displayName != null && user.displayName!.isNotEmpty)
        ? user.displayName!
        : (user.username.isNotEmpty ? user.username : 'Nearby user');
    final bio = user.bio ?? 'Nearby connect user';
    final interests = user.interests ?? const ['Chat', 'Local', 'Nearby'];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClayCard(
        padding: const EdgeInsets.all(16.0),
        borderRadius: 20.0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Circular neutral avatar with online dot pinned to bottom-right
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border, width: 0.8),
                      ),
                      child: ClipOval(
                        child: (user.avatarUrl != null && user.avatarUrl!.isNotEmpty)
                            ? Image.network(
                                user.avatarUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _buildAvatarFallback(nameToDisplay),
                              )
                            : _buildAvatarFallback(nameToDisplay),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 13,
                        height: 13,
                        decoration: BoxDecoration(
                          color: user.isOnline ? AppColors.success : AppColors.disabled,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2.2),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 14),

                // Name & Distance
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              nameToDisplay,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                color: AppColors.textPrimary,
                                letterSpacing: -0.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isNewHere) ...[
                            const SizedBox(width: 6),
                            const ClayBadge(label: 'New here', isHighlighted: true),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${user.formattedDistance} away',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Unread Badge if present
                if (unreadCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ClayBadge(label: '$unreadCount', isHighlighted: true),
                  ),

                // Message Action Button (White circular tactile button with blue chat bubble)
                if (isProcessing)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                  )
                else
                  _buildActionButtons(context),
              ],
            ),

            if (bio.isNotEmpty && bio != 'Nearby connect user') ...[
              const SizedBox(height: 10),
              Text(
                bio,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textSecondary,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            // Interest Chips
            if (interests.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: interests
                    .take(3)
                    .map((interest) => ClayBadge(label: interest.startsWith('#') ? interest.substring(1) : interest))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarFallback(String name) {
    return Center(
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : 'U',
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    if (request != null && request!.status == ChatRequestStatus.accepted) {
      return ClayCircleButton(
        icon: Icons.chat_bubble_rounded,
        iconColor: AppColors.primary,
        size: 42,
        iconSize: 18,
        tooltip: 'Open chat',
        onPressed: onTapChat,
      );
    }

    if (!user.withinChatRadius) {
      return const ClayCircleButton(
        icon: Icons.location_off_outlined,
        iconColor: AppColors.disabled,
        size: 42,
        iconSize: 18,
        tooltip: 'Outside 1 km',
        onPressed: null,
      );
    }

    if (user.isLocationStale) {
      return const ClayCircleButton(
        icon: Icons.schedule_rounded,
        iconColor: AppColors.disabled,
        size: 42,
        iconSize: 18,
        tooltip: 'Updating location...',
        onPressed: null,
      );
    }

    if (request == null || request!.status == ChatRequestStatus.none || request!.status == ChatRequestStatus.cancelled) {
      return ClayCircleButton(
        icon: Icons.chat_bubble_rounded,
        iconColor: AppColors.primary,
        size: 42,
        iconSize: 18,
        tooltip: 'Message',
        onPressed: onSendRequest,
      );
    }

    if (request!.status == ChatRequestStatus.pending) {
      final isSender = request!.senderId == currentUserId;
      if (isSender) {
        return const ClayCircleButton(
          icon: Icons.hourglass_top_rounded,
          iconColor: AppColors.primary,
          size: 42,
          iconSize: 18,
          tooltip: 'Request pending',
          onPressed: null,
        );
      } else {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClayCircleButton(
              icon: Icons.close_rounded,
              iconColor: AppColors.danger,
              size: 36,
              iconSize: 16,
              tooltip: 'Deny',
              onPressed: onDeny,
            ),
            const SizedBox(width: 8),
            ClayCircleButton(
              icon: Icons.check_rounded,
              iconColor: AppColors.success,
              size: 36,
              iconSize: 16,
              tooltip: 'Accept',
              onPressed: onAccept,
            ),
          ],
        );
      }
    }

    if (request!.status == ChatRequestStatus.denied) {
      final isSender = request!.senderId == currentUserId;
      return ClayCircleButton(
        icon: Icons.refresh_rounded,
        iconColor: isSender ? AppColors.disabled : AppColors.primary,
        size: 42,
        iconSize: 18,
        tooltip: isSender ? 'Declined' : 'Request again',
        onPressed: onSendRequest,
      );
    }

    return ClayCircleButton(
      icon: Icons.chat_bubble_rounded,
      iconColor: AppColors.primary,
      size: 42,
      iconSize: 18,
      tooltip: 'Message',
      onPressed: onSendRequest,
    );
  }
}

class _LoadingRadarSkeleton extends StatelessWidget {
  final AnimationController animationController;

  const _LoadingRadarSkeleton({required this.animationController});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 90,
            height: 90,
            child: AnimatedBuilder(
              animation: animationController,
              builder: (context, child) {
                return CustomPaint(
                  painter: _RadarRipplePainter(
                    progress: animationController.value,
                    color: AppColors.primary,
                  ),
                  child: Center(
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border, width: 0.8),
                      ),
                      padding: const EdgeInsets.all(10),
                      child: const EasyChatLogoMark(size: 32),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Discovering nearby people',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Searching within 1 km radius',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationDisabledCard extends StatelessWidget {
  final String errorMessage;
  final VoidCallback onRetry;

  const _LocationDisabledCard({required this.errorMessage, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: ClayCard(
          padding: const EdgeInsets.all(24.0),
          borderRadius: BorderRadius.circular(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: const BoxDecoration(
                  color: AppColors.surfaceVariant,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.location_off_outlined, size: 32, color: AppColors.icon),
              ),
              const SizedBox(height: 16),
              const Text(
                'Location access needed',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                errorMessage.isNotEmpty
                    ? errorMessage
                    : 'Easy Chat needs your location to discover people within 1 km.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              ClayButton(
                label: 'Enable location and retry',
                icon: Icons.near_me_outlined,
                onPressed: onRetry,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyNearbyState extends StatelessWidget {
  final VoidCallback onScan;

  const _EmptyNearbyState({required this.onScan});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
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
              child: const EasyChatLogoMark(size: 42),
            ),
            const SizedBox(height: 20),
            const Text(
              'No one nearby right now',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'When people within 1 km open Easy Chat, they will appear here automatically.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            ClayButton(
              label: 'Scan again',
              icon: Icons.radar_outlined,
              onPressed: onScan,
            ),
          ],
        ),
      ),
    );
  }
}

