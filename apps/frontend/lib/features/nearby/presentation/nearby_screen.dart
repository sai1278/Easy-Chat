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

class _NearbyScreenState extends ConsumerState<NearbyScreen> {
  StreamSubscription<Position>? _positionSub;
  Position? _currentPosition;
  bool _isInitializing = true;
  bool _locationUnavailable = false;
  String _locationErrorMessage = '';

  Timer? _heartbeatTimer;

  @override
  void initState() {
    super.initState();
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
            icon: const Icon(Icons.sync),
            tooltip: 'Refresh Peers',
            onPressed: () => _initializeLocationAndDiscovery(),
          )
        ],
      ),
      body: Column(
        children: [
          // Proximity Sensor Duty-Cycle Power Optimization Registry Panel
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                      Icon(Icons.bolt_rounded, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Sensor & Battery Engine',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                      ),
                      const Spacer(),
                      Chip(
                        avatar: Icon(
                          activity == ActivityState.moving ? Icons.directions_walk : Icons.accessibility_new,
                          size: 16,
                          color: colorScheme.onSecondaryContainer,
                        ),
                        label: Text(
                          activity == ActivityState.moving ? 'Moving (5m filter)' : 'Stationary (2m filter)',
                          style: TextStyle(fontSize: 11, color: colorScheme.onSecondaryContainer),
                        ),
                        backgroundColor: colorScheme.secondaryContainer,
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.gps_fixed, size: 14, color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          gpsInfo,
                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.bluetooth_searching, size: 14, color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          bleInfo,
                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                  if (_currentPosition != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'My GPS Coordinates: ${_currentPosition!.latitude.toStringAsFixed(4)}, ${_currentPosition!.longitude.toStringAsFixed(4)}',
                      style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant.withOpacity(0.8)),
                    ),
                  ],
                ],
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.radar_rounded, color: colorScheme.secondary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Discovered Nearby Peers',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                Text(
                  '${users.length} active',
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),

          Expanded(
            child: _isInitializing
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: colorScheme.primary),
                        const SizedBox(height: 16),
                        Text(
                          'Scanning nearby spatial region...',
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  )
                : _locationUnavailable
                    ? Center(
                        child: Card(
                          margin: const EdgeInsets.all(24),
                          color: colorScheme.errorContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.location_off_rounded, size: 48, color: colorScheme.onErrorContainer),
                                const SizedBox(height: 16),
                                Text(
                                  'Location Access Disabled',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onErrorContainer,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _locationErrorMessage.isNotEmpty
                                      ? _locationErrorMessage
                                      : 'Unable to acquire GPS signal. Please enable high accuracy location services.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: colorScheme.onErrorContainer.withOpacity(0.9)),
                                ),
                                const SizedBox(height: 16),
                                FilledButton.icon(
                                  onPressed: () => _initializeLocationAndDiscovery(),
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Grant & Retry GPS'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : users.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32.0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(24),
                                    decoration: BoxDecoration(
                                      color: colorScheme.secondaryContainer.withOpacity(0.5),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(Icons.sensors_off_rounded, size: 48, color: colorScheme.secondary),
                                  ),
                                  const SizedBox(height: 20),
                                  Text(
                                    'No Nearby Devices Discovered',
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Ensure another device is online and within 5km distance.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                                  ),
                                  const SizedBox(height: 20),
                                  FilledButton.icon(
                                    onPressed: () => _fetchNearbyUsers(),
                                    icon: const Icon(Icons.radar_rounded),
                                    label: const Text('Scan Spatial Area'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            itemCount: users.length,
                            itemBuilder: (context, index) {
                              final user = users[index];
                              final unreadCounts = ref.watch(unreadCountsProvider);
                              final unreadCount = unreadCounts[user.userId] ?? 0;

                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                color: colorScheme.surfaceContainerLow,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.4)),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Row(
                                    children: [
                                      Stack(
                                        children: [
                                          CircleAvatar(
                                            radius: 26,
                                            backgroundColor: colorScheme.primaryContainer,
                                            child: Text(
                                              user.username.isNotEmpty ? user.username[0].toUpperCase() : 'U',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: colorScheme.onPrimaryContainer,
                                              ),
                                            ),
                                          ),
                                          Positioned(
                                            right: 0,
                                            bottom: 0,
                                            child: Container(
                                              width: 14,
                                              height: 14,
                                              decoration: BoxDecoration(
                                                color: user.isOnline ? Colors.green : Colors.grey,
                                                shape: BoxShape.circle,
                                                border: Border.all(color: colorScheme.surface, width: 2),
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
                                            Text(
                                              user.username,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: colorScheme.secondaryContainer,
                                                    borderRadius: BorderRadius.circular(8),
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
                                                const SizedBox(width: 6),
                                                Text(
                                                  user.isOnline ? 'Active now' : 'Offline',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: colorScheme.onSurfaceVariant,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (unreadCount > 0)
                                        Badge(
                                          label: Text('$unreadCount'),
                                          backgroundColor: colorScheme.error,
                                        ),
                                      const SizedBox(width: 8),
                                      FilledButton.tonalIcon(
                                        icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                                        label: const Text('Chat'),
                                        onPressed: () => _startChatWithUser(user),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
