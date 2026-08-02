import 'dart:convert';
import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'core/database/isar_service.dart';
import 'core/navigation/app_router.dart';
import 'core/network/dio_client.dart';
import 'core/network/environment.dart';
import 'core/network/websocket_client.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/battery_optimizer.dart';
import 'features/chat/data/chat_repository.dart';
import 'features/chat/presentation/chat_controller.dart';
import 'features/profile/data/profile_repository.dart';
import 'features/nearby/presentation/nearby_screen.dart';
import 'features/nearby/domain/proximity_user.dart';

import 'core/database/entities/message_entity.dart';

final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

final webSocketClientProvider = Provider<WebSocketClient>((ref) => throw UnimplementedError());

final unreadCountsProvider = StateProvider<Map<String, int>>((ref) => {});

final incomingMessageStreamProvider = StreamProvider.autoDispose<MessageEntity?>((ref) {
  final repo = ref.watch(chatRepositoryProvider);
  return repo.incomingMessages;
});

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = ApiConfig.fromEnvironment();
  dev.log('[NetworkConfig] Effective API Base URL: ${config.baseUrl}', name: 'NetworkConfig');
  dev.log('[NetworkConfig] Effective WebSocket URL: ${config.wsUrl}', name: 'NetworkConfig');

  // 1. Initialize Isar offline-first local database cache
  final isarService = await IsarService.init();

  // 2. Initialize Network Clients
  final dioClient = DioClient();
  final wsClient = WebSocketClient();

  const currentUserId = String.fromEnvironment('USER_ID');
  const jwtToken = String.fromEnvironment('JWT_TOKEN');

  // Parse authenticated UUID from JWT 'sub' claim dynamically
  String effectiveUserId = currentUserId;
  if (jwtToken.isNotEmpty) {
    await dioClient.updateToken(jwtToken);
    try {
      final parts = jwtToken.split('.');
      if (parts.length == 3) {
        final payload = parts[1];
        final normalized = payload.padRight(payload.length + ((4 - payload.length % 4) % 4), '=');
        final payloadMap = jsonDecode(utf8.decode(base64Url.decode(normalized))) as Map<String, dynamic>;
        final sub = payloadMap['sub'] as String?;
        if (sub != null && sub.isNotEmpty) {
          effectiveUserId = sub;
        }
      }
    } catch (_) {}
  }

  runApp(
    ProviderScope(
      overrides: [
        webSocketClientProvider.overrideWithValue(wsClient),
        profileRepositoryProvider.overrideWith((ref) => ProfileRepository(
              isar: isarService,
              dioClient: dioClient,
            )),
        // Override repository provider with initialized instance
        chatRepositoryProvider.overrideWith((ref) {
          final repo = ChatRepository(
            isar: isarService,
            dioClient: dioClient,
            wsClient: wsClient,
            currentUserId: effectiveUserId,
          );

          // Start receiving WebSocket events for active user session after build frame completes
          if (jwtToken.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              repo.startWebSocketListener(jwtToken);
            });
          }

          ref.onDispose(() => repo.close());
          return repo;
        }),
      ],
      child: const NearbyConnectApp(),
    ),
  );
}

class NearbyConnectApp extends ConsumerStatefulWidget {
  const NearbyConnectApp({super.key});

  @override
  ConsumerState<NearbyConnectApp> createState() => _NearbyConnectAppState();
}

class _NearbyConnectAppState extends ConsumerState<NearbyConnectApp>
    with WidgetsBindingObserver {
  late final BatteryOptimizer _batteryOptimizer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 3. Initialize dynamic sensor battery optimization engine
    _batteryOptimizer = BatteryOptimizer(
      onLocationSettingsChanged: (LocationSettings settings) {
        ref.read(gpsSettingsProvider.notifier).state =
            'Accuracy: ${settings.accuracy.name} • Filter: ${settings.distanceFilter}m';
      },
      onBleScanTrigger: (bool startScan, ScanMode scanMode) {
        ref.read(bleDutyCycleProvider.notifier).state = startScan
            ? 'BLE Scan active (5s) [${scanMode.name}]'
            : 'BLE Scan standby';
      },
    );

    // Bootstrap optimizations and eager repository initialization after the build frame completes
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _batteryOptimizer.start();
      final repo = ref.read(chatRepositoryProvider);
      await repo.ensureConnected();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _batteryOptimizer.setLifecycleState(state);
    
    // Reduce WebSocket heartbeat ping chatter when backgrounded (50s instead of 30s)
    try {
      final ws = ref.read(webSocketClientProvider);
      if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
        ws.setHeartbeatInterval(const Duration(seconds: 50));
      } else {
        ws.setHeartbeatInterval(const Duration(seconds: 30));
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _batteryOptimizer.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Dynamically adjust BLE scanning frequency based on user density changes
    ref.listen<List<ProximityUser>>(proximityUsersProvider, (previous, next) {
      _batteryOptimizer.setNearbyDeviceDensity(next.length);
    });

    // Listen for incoming WebSocket message notifications globally
    ref.listen<AsyncValue<MessageEntity?>>(incomingMessageStreamProvider, (prev, next) {
      next.whenData((msg) {
        if (msg == null) return;
        final chatRepo = ref.read(chatRepositoryProvider);
        if (chatRepo.activeRoomId == msg.roomId) return; // User is already in this chat room

        // Increment unread count for the sender
        ref.read(unreadCountsProvider.notifier).update((state) {
          final map = Map<String, int>.from(state);
          map[msg.senderId] = (map[msg.senderId] ?? 0) + 1;
          return map;
        });

        final text = String.fromCharCodes(msg.encryptedPayload);
        final messenger = rootScaffoldMessengerKey.currentState;
        messenger?.hideCurrentSnackBar();
        messenger?.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.chat_bubble_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'New Message',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.teal.shade800,
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'View',
              textColor: Colors.amber,
              onPressed: () {
                AppRouter.router.go('/chat/${msg.roomId}?peerId=${msg.senderId}');
              },
            ),
          ),
        );
      });
    });

    // 4. Bind root router to GoRouter declarative navigator with Material 3 Theme System
    return MaterialApp.router(
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      title: 'Nearby Connect',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: AppRouter.router,
      debugShowCheckedModeBanner: false,
    );
  }
}

