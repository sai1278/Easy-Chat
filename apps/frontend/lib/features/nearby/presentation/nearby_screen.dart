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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Proximity Discovery'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _initializeLocationAndDiscovery(),
          )
        ],
      ),
      body: Column(
        children: [
          // Proximity Sensor Duty-Cycle Optimization State Panel
          Card(
            margin: const EdgeInsets.all(12),
            elevation: 3,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.battery_charging_full, color: Colors.green),
                      const SizedBox(width: 8),
                      Text(
                        'Power Optimization Registry',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('User Activity:'),
                      Chip(
                        label: Text(activity == ActivityState.moving ? 'Moving' : 'Stationary'),
                        backgroundColor: activity == ActivityState.moving
                            ? Colors.orange.shade100
                            : Colors.blue.shade100,
                      )
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('GPS Resolution:'),
                      Text(gpsInfo, style: const TextStyle(fontWeight: FontWeight.w500)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('BLE Scan State:'),
                      Text(bleInfo, style: const TextStyle(fontWeight: FontWeight.w500)),
                    ],
                  ),
                  if (_currentPosition != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'My Location: ${_currentPosition!.latitude.toStringAsFixed(4)}, ${_currentPosition!.longitude.toStringAsFixed(4)}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.radar, color: Colors.teal),
                SizedBox(width: 8),
                Text(
                  'Active Nearby Peers',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isInitializing
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Searching for nearby devices...'),
                      ],
                    ),
                  )
                : _locationUnavailable
                    ? Center(
                        child: Card(
                          margin: const EdgeInsets.all(16),
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.location_off, size: 48, color: Colors.orange),
                                const SizedBox(height: 16),
                                const Text(
                                  'Location Unavailable',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _locationErrorMessage.isNotEmpty
                                      ? _locationErrorMessage
                                      : 'Unable to acquire GPS fix. Please ensure location services are enabled.',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.grey),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: () => _initializeLocationAndDiscovery(),
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Retry Location Acquisition'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : users.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.devices_other, size: 64, color: Colors.grey.shade400),
                                const SizedBox(height: 16),
                                const Text(
                                  'No nearby users found within 5km radius.',
                                  style: TextStyle(fontSize: 15, color: Colors.grey),
                                ),
                                const SizedBox(height: 8),
                                ElevatedButton.icon(
                                  onPressed: () => _fetchNearbyUsers(),
                                  icon: const Icon(Icons.search),
                                  label: const Text('Scan Now'),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: users.length,
                            itemBuilder: (context, index) {
                              final user = users[index];
                              final unreadCounts = ref.watch(unreadCountsProvider);
                              final unreadCount = unreadCounts[user.userId] ?? 0;

                              return Card(
                                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: user.isOnline ? Colors.teal : Colors.grey,
                                    child: Text(
                                      user.username.isNotEmpty ? user.username[0].toUpperCase() : 'U',
                                      style: const TextStyle(color: Colors.white),
                                    ),
                                  ),
                                  title: Text(
                                    user.username,
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Text(
                                    '${user.distanceMeters.toStringAsFixed(1)}m away • ${user.isOnline ? "Online" : "Offline"}',
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (unreadCount > 0)
                                        Container(
                                          margin: const EdgeInsets.only(right: 8),
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.red,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            '$unreadCount',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ElevatedButton.icon(
                                        icon: const Icon(Icons.chat_bubble_outline, size: 18),
                                        label: const Text('Chat'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.teal,
                                          foregroundColor: Colors.white,
                                        ),
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
