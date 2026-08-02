import 'dart:async';
import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/utils/battery_optimizer.dart';
import '../../../core/services/location_service.dart';
import '../../auth/data/auth_repository.dart';
import '../../chat/presentation/chat_controller.dart';
import '../data/nearby_repository.dart';
import '../domain/proximity_user.dart';
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
  Position? _currentPosition;
  bool _isInitializing = true;
  bool _locationUnavailable = false;
  String _locationErrorMessage = '';

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatRepositoryProvider).ensureConnected();
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
          _fetchNearbyUsers(pos.latitude, pos.longitude);
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

  Future<void> _fetchNearbyUsers([double? lat, double? lng]) async {
    double? useLat = lat ?? _currentPosition?.latitude;
    double? useLng = lng ?? _currentPosition?.longitude;

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
        if (mounted) {
          setState(() => _currentPosition = pos);
        }
      } catch (e) {
        try {
          final lastPos = await Geolocator.getLastKnownPosition();
          if (lastPos != null) {
            useLat = lastPos.latitude;
            useLng = lastPos.longitude;
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
    await nearbyRepo.sendLocationHeartbeat(useLat, useLng);
    final users = await nearbyRepo.fetchNearbyUsers(latitude: useLat, longitude: useLng);

    if (mounted) {
      ref.read(proximityUsersProvider.notifier).state = users;
      if (_isInitializing) {
        setState(() => _isInitializing = false);
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

    try {
      final dioClient = DioClient();
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
          context.push('/chat/$roomId?peerId=${peer.userId}');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to initiate chat room: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _heartbeatTimer?.cancel();
    _radarAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(proximityUsersProvider);
    final activity = ref.watch(batteryStateProvider);
    final gpsInfo = ref.watch(gpsSettingsProvider);
    final bleInfo = ref.watch(bleDutyCycleProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Spatial Discovery'),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle_rounded),
            tooltip: 'My Profile',
            onPressed: () => context.push('/profile'),
          ),
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Refresh Peers',
            onPressed: () => _initializeLocationAndDiscovery(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Premium Radar Pulse & Sensor Panel Banner
          _RadarHeaderBanner(
            animationController: _radarAnimationController,
            activity: activity,
            gpsInfo: gpsInfo,
            bleInfo: bleInfo,
            currentPosition: _currentPosition,
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.radar_rounded, color: colorScheme.primary, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Discovered Nearby Peers',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${users.length} active nearby',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSecondaryContainer,
                    ),
                  ),
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
                    : users.isEmpty
                        ? _EmptyNearbyState(onScan: _fetchNearbyUsers)
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            itemCount: users.length,
                            itemBuilder: (context, index) {
                              final user = users[index];
                              final unreadCounts = ref.watch(unreadCountsProvider);
                              final unreadCount = unreadCounts[user.userId] ?? 0;

                              return _NearbyUserCard(
                                key: ValueKey(user.userId),
                                user: user,
                                unreadCount: unreadCount,
                                onTapChat: () => _startChatWithUser(user),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class _RadarHeaderBanner extends StatelessWidget {
  final AnimationController animationController;
  final ActivityState activity;
  final String gpsInfo;
  final String bleInfo;
  final Position? currentPosition;

  const _RadarHeaderBanner({
    required this.animationController,
    required this.activity,
    required this.gpsInfo,
    required this.bleInfo,
    this.currentPosition,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: colorScheme.surfaceContainerLow,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            // Radar Animation Ripple Circle
            SizedBox(
              width: 56,
              height: 56,
              child: AnimatedBuilder(
                animation: animationController,
                builder: (context, child) {
                  return CustomPaint(
                    painter: _RadarRipplePainter(
                      progress: animationController.value,
                      color: colorScheme.primary,
                    ),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.wifi_tethering_rounded, color: colorScheme.onPrimaryContainer, size: 24),
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
                        'Sensor Power Engine',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          activity == ActivityState.moving ? 'Moving (5m)' : 'Stationary (2m)',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: colorScheme.onSecondaryContainer),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.gps_fixed_rounded, size: 12, color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          gpsInfo,
                          style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.bluetooth_searching_rounded, size: 12, color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          bleInfo,
                          style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ],
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
        ..color = color.withOpacity(opacity * 0.4)
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

class _NearbyUserCard extends StatelessWidget {
  final ProximityUser user;
  final int unreadCount;
  final VoidCallback onTapChat;

  const _NearbyUserCard({
    super.key,
    required this.user,
    required this.unreadCount,
    required this.onTapChat,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayName = user.displayName ?? user.username;
    final bio = user.bio ?? 'Nearby Connect Ephemeral Peer';
    final interests = user.interests ?? const ['Flutter', 'Go', 'P2P', 'BLE Mesh'];
    final rssiVal = user.rssi ?? -60;
    final signalText = rssiVal > -70 ? 'Strong (-${rssiVal.abs()} dBm)' : 'Good (-${rssiVal.abs()} dBm)';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: colorScheme.surfaceContainerLow,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Large Avatar with Online Status Ring
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: colorScheme.primaryContainer,
                      backgroundImage: user.avatarUrl != null && user.avatarUrl!.isNotEmpty
                          ? NetworkImage(user.avatarUrl!) as ImageProvider
                          : null,
                      child: (user.avatarUrl == null || user.avatarUrl!.isEmpty)
                          ? Text(
                              displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onPrimaryContainer,
                              ),
                            )
                          : null,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: user.isOnline ? Colors.green : Colors.grey,
                          shape: BoxShape.circle,
                          border: Border.all(color: colorScheme.surface, width: 2.5),
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
                              displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${user.distanceMeters.toStringAsFixed(1)}m away',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '@${user.username} • ${user.isOnline ? 'Active now' : 'Last seen recently'}',
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.wifi_tethering_rounded, size: 13, color: colorScheme.primary),
                          const SizedBox(width: 4),
                          Text(
                            signalText,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: colorScheme.primary),
                          ),
                        ],
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
              style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),

            // Shared Interests ChoiceChips
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: interests
                  .map(
                    (interest) => Chip(
                      label: Text('#$interest', style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant)),
                      backgroundColor: colorScheme.surfaceContainerHigh,
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 14),

            // "Tap to Chat" CTA FilledButton
            Row(
              children: [
                if (unreadCount > 0) ...[
                  Badge(
                    label: Text('$unreadCount unread'),
                    backgroundColor: colorScheme.error,
                  ),
                  const Spacer(),
                ] else
                  const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: onTapChat,
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                  label: const Text('Tap to Chat'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingRadarSkeleton extends StatelessWidget {
  final AnimationController animationController;

  const _LoadingRadarSkeleton({required this.animationController});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

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
                    color: colorScheme.primary,
                  ),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.radar_rounded, size: 36, color: colorScheme.onPrimaryContainer),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Scanning nearby spatial area...',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'Discovering BLE mesh & GPS active peers within range',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
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
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Card(
        margin: const EdgeInsets.all(24),
        color: colorScheme.errorContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_off_rounded, size: 48, color: colorScheme.onErrorContainer),
              const SizedBox(height: 16),
              Text(
                'Location Access Required',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onErrorContainer,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                errorMessage.isNotEmpty
                    ? errorMessage
                    : 'Location services or permissions are disabled. Please enable high accuracy location.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colorScheme.onErrorContainer.withOpacity(0.9)),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.gps_fixed_rounded),
                label: const Text('Enable Location & Retry'),
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
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.sensors_off_rounded, size: 52, color: colorScheme.secondary),
            ),
            const SizedBox(height: 24),
            Text(
              'No Nearby Users Found',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ensure another active user has Nearby Connect open on a nearby device within range.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onScan,
              icon: const Icon(Icons.radar_rounded),
              label: const Text('Scan Spatial Area Again'),
            ),
          ],
        ),
      ),
    );
  }
}
