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

    return Scaffold(
      appBar: AppBar(
        backgroundColor: ClayColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        title: Row(
          children: [
            const EasyChatLogoMark(size: 32),
            const SizedBox(width: 10),
            Text(
              'Easy Chat',
              style: TextStyle(
                color: ClayColors.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 20,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: ClayColors.cardSurface,
                shape: BoxShape.circle,
                boxShadow: ClayShadows.button,
              ),
              child: Icon(Icons.sync_rounded, size: 18, color: ClayColors.textSecondary),
            ),
            tooltip: 'Refresh',
            onPressed: () => _initializeLocationAndDiscovery(),
          ),
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: ClayColors.cardSurface,
                shape: BoxShape.circle,
                boxShadow: ClayShadows.button,
              ),
              child: Icon(Icons.person_outline_rounded, size: 18, color: ClayColors.textSecondary),
            ),
            tooltip: 'My Profile',
            onPressed: () => context.push('/profile'),
          ),
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: ClayColors.cardSurface,
                shape: BoxShape.circle,
                boxShadow: ClayShadows.button,
              ),
              child: Icon(Icons.settings_outlined, size: 18, color: ClayColors.textSecondary),
            ),
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      backgroundColor: ClayColors.background,
      body: Column(
        children: [
          // Premium Clay Radar Discovery Banner
          _RadarHeaderBanner(
            animationController: _radarAnimationController,
            currentPosition: _currentPosition,
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Text(
                  'People Nearby',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: ClayColors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                const Spacer(),
                ClayBadge(
                  label: '${users.length} nearby',
                  isHighlighted: users.isNotEmpty,
                ),
              ],
            ),
          ),

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
                                const SizedBox(height: 16),
                              ],
                              ...users.map((user) {
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

class _RadarHeaderBanner extends StatelessWidget {
  final AnimationController animationController;
  final Position? currentPosition;

  const _RadarHeaderBanner({
    required this.animationController,
    this.currentPosition,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ClayCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Radar Animation Ripple Circle with Official Logo center
            SizedBox(
              width: 56,
              height: 56,
              child: AnimatedBuilder(
                animation: animationController,
                builder: (context, child) {
                  return RepaintBoundary(
                    child: CustomPaint(
                      painter: _RadarRipplePainter(
                        progress: animationController.value,
                        color: ClayColors.accent,
                      ),
                      child: Center(
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: ClayShadows.card,
                          ),
                          padding: const EdgeInsets.all(6),
                          child: const EasyChatLogoMark(size: 26),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 16),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Discovery Active',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: ClayColors.textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const Spacer(),
                      ClayBadge(
                        label: '1 km limit',
                        isHighlighted: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Looking for people within 1 km walking distance',
                    style: TextStyle(
                      fontSize: 12,
                      color: ClayColors.textSecondary,
                      height: 1.3,
                    ),
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
      padding: const EdgeInsets.all(16.0),
      borderRadius: BorderRadius.circular(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: ClayColors.accentLight,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.mark_chat_unread_rounded, color: ClayColors.accent, size: 16),
              ),
              const SizedBox(width: 10),
              Text(
                'Chat Requests (${requests.length})',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: ClayColors.textPrimary,
                  letterSpacing: -0.3,
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
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: ClayColors.cardSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: ClayColors.borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: ClayColors.accentLight,
                        backgroundImage: req.senderAvatarUrl != null && req.senderAvatarUrl!.isNotEmpty
                            ? NetworkImage(req.senderAvatarUrl!) as ImageProvider
                            : null,
                        child: (req.senderAvatarUrl == null || req.senderAvatarUrl!.isEmpty)
                            ? Text(
                                senderName.isNotEmpty ? senderName[0].toUpperCase() : 'U',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: ClayColors.accent,
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
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: ClayColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              bio,
                              style: TextStyle(
                                fontSize: 12,
                                color: ClayColors.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        timeStr,
                        style: TextStyle(
                          fontSize: 11,
                          color: ClayColors.textSecondary,
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
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2, color: ClayColors.accent),
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
    required this.onTapChat,
    required this.onSendRequest,
    this.onAccept,
    this.onDeny,
  });

  @override
  Widget build(BuildContext context) {
    final nameToDisplay = (user.displayName != null && user.displayName!.isNotEmpty)
        ? user.displayName!
        : (user.username.isNotEmpty ? user.username : 'Nearby User');
    final bio = user.bio ?? 'Nearby Connect User';
    final interests = user.interests ?? const ['Chat', 'Local', 'Nearby'];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClayCard(
        padding: const EdgeInsets.all(16.0),
        borderRadius: BorderRadius.circular(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Soft Clay Avatar with Online Indicator
                Stack(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: ClayColors.cardSurface,
                        shape: BoxShape.circle,
                        boxShadow: ClayShadows.card,
                        border: Border.all(color: ClayColors.borderSubtle, width: 1.5),
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
                      right: 1,
                      bottom: 1,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: user.isOnline ? const Color(0xFF10B981) : const Color(0xFF9CA3AF),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 14),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              nameToDisplay,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                color: ClayColors.textPrimary,
                                letterSpacing: -0.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Simple Human-Friendly Distance Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: !user.withinChatRadius
                                  ? const Color(0xFFFEE2E2)
                                  : user.isLocationStale
                                      ? const Color(0xFFFEF3C7)
                                      : ClayColors.accentLight,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  !user.withinChatRadius
                                      ? Icons.location_off_rounded
                                      : user.isLocationStale
                                          ? Icons.schedule_rounded
                                          : Icons.near_me_rounded,
                                  size: 11,
                                  color: !user.withinChatRadius
                                      ? const Color(0xFFDC2626)
                                      : user.isLocationStale
                                          ? const Color(0xFFD97706)
                                          : ClayColors.accent,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  !user.withinChatRadius
                                      ? 'Outside 1 km'
                                      : user.isLocationStale
                                          ? 'Updating...'
                                          : user.formattedDistance,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: !user.withinChatRadius
                                        ? const Color(0xFFDC2626)
                                        : user.isLocationStale
                                            ? const Color(0xFFD97706)
                                            : ClayColors.accent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user.isOnline ? 'Active nearby' : 'Seen recently',
                        style: TextStyle(fontSize: 12, color: ClayColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Short Bio
            Text(
              bio,
              style: TextStyle(fontSize: 13, color: ClayColors.textPrimary, height: 1.35),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),

            // Subtle Interest Pills
            if (interests.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: interests
                    .take(4)
                    .map(
                      (interest) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: ClayColors.cardSurface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: ClayColors.borderSubtle),
                        ),
                        child: Text(
                          '#$interest',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: ClayColors.textSecondary,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            const SizedBox(height: 14),

            // Action Buttons Row
            Row(
              children: [
                if (unreadCount > 0) ...[
                  ClayBadge(label: '$unreadCount unread', isHighlighted: true),
                  const SizedBox(width: 8),
                ],
                const Spacer(),
                if (isProcessing)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: ClayColors.accent),
                  )
                else
                  _buildActionButtons(context),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarFallback(String name) {
    return Center(
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : 'U',
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: ClayColors.accent,
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    // 1. Existing accepted relationships remain accessible regardless of current location
    if (request != null && request!.status == ChatRequestStatus.accepted) {
      return ClayButton(
        label: 'Open Chat',
        icon: Icons.chat_bubble_rounded,
        onPressed: onTapChat,
      );
    }

    // 2. Strict 1 KM Proximity Rule: Block initiating or accepting requests when outside 1.0 km
    if (!user.withinChatRadius) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_off_rounded, size: 14, color: Colors.red.shade400),
            const SizedBox(width: 6),
            Text(
              'Outside 1 km radius',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.red.shade600,
              ),
            ),
          ],
        ),
      );
    }

    // 3. Reject stale location (>60s)
    if (user.isLocationStale) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF3C7),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule_rounded, size: 14, color: Colors.amber.shade700),
            const SizedBox(width: 6),
            Text(
              'Location updating...',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.amber.shade800,
              ),
            ),
          ],
        ),
      );
    }

    if (request == null || request!.status == ChatRequestStatus.none || request!.status == ChatRequestStatus.cancelled) {
      return ClayButton(
        label: 'Send Request',
        icon: Icons.person_add_rounded,
        onPressed: onSendRequest,
      );
    }

    if (request!.status == ChatRequestStatus.pending) {
      final isSender = request!.senderId == currentUserId;
      if (isSender) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: ClayColors.cardSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: ClayColors.borderSubtle),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hourglass_top_rounded, size: 14, color: ClayColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                'Request Pending',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: ClayColors.textSecondary,
                ),
              ),
            ],
          ),
        );
      } else {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClaySecondaryButton(
              label: 'Deny',
              icon: Icons.close_rounded,
              onPressed: onDeny,
            ),
            const SizedBox(width: 8),
            ClayButton(
              label: 'Accept',
              icon: Icons.check_rounded,
              onPressed: onAccept,
            ),
          ],
        );
      }
    }

    if (request!.status == ChatRequestStatus.accepted) {
      return ClayButton(
        label: 'Open Chat',
        icon: Icons.chat_bubble_rounded,
        onPressed: onTapChat,
      );
    }

    if (request!.status == ChatRequestStatus.denied) {
      final isSender = request!.senderId == currentUserId;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              isSender ? 'Declined' : 'Denied',
              style: const TextStyle(fontSize: 11, color: Color(0xFFDC2626), fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
          ClaySecondaryButton(
            label: 'Request Again',
            icon: Icons.refresh_rounded,
            onPressed: onSendRequest,
          ),
        ],
      );
    }

    return ClayButton(
      label: 'Send Request',
      icon: Icons.person_add_rounded,
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
            width: 100,
            height: 100,
            child: AnimatedBuilder(
              animation: animationController,
              builder: (context, child) {
                return CustomPaint(
                  painter: _RadarRipplePainter(
                    progress: animationController.value,
                    color: ClayColors.accent,
                  ),
                  child: Center(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: ClayShadows.card,
                      ),
                      padding: const EdgeInsets.all(10),
                      child: const EasyChatLogoMark(size: 36),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Discovering nearby people...',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: ClayColors.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Searching within 1 km radius',
            style: TextStyle(fontSize: 13, color: ClayColors.textSecondary),
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
          borderRadius: BorderRadius.circular(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: ClayColors.accentLight,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.location_off_rounded, size: 36, color: ClayColors.accent),
              ),
              const SizedBox(height: 18),
              Text(
                'Location Access Needed',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: ClayColors.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                errorMessage.isNotEmpty
                    ? errorMessage
                    : 'Easy Chat needs your location to discover people within 1 km.',
                textAlign: TextAlign.center,
                style: TextStyle(color: ClayColors.textSecondary, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 20),
              ClayButton(
                label: 'Enable Location & Retry',
                icon: Icons.near_me_rounded,
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
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: ClayShadows.card,
              ),
              child: const EasyChatLogoMark(size: 48),
            ),
            const SizedBox(height: 24),
            Text(
              'No One Nearby Right Now',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: ClayColors.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'When people within 1 km open Easy Chat, they will appear here automatically.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: ClayColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 24),
            ClayButton(
              label: 'Scan Again',
              icon: Icons.radar_rounded,
              onPressed: onScan,
            ),
          ],
        ),
      ),
    );
  }
}

