import 'dart:convert';
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
import 'features/chat/domain/chat_request.dart';
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

  // Print startup banner with build mode & environment details
  EnvironmentService.printStartupBanner();

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
        dioClientProvider.overrideWithValue(dioClient),
        isarServiceProvider.overrideWithValue(isarService),
        webSocketClientProvider.overrideWithValue(wsClient),
        profileRepositoryProvider.overrideWith((ref) => ProfileRepository(
              isar: isarService,
              dioClient: ref.watch(dioClientProvider),
            )),
        chatRepositoryProvider.overrideWith((ref) {
          final repo = ChatRepository(
            isar: isarService,
            dioClient: ref.watch(dioClientProvider),
            wsClient: wsClient,
            currentUserId: effectiveUserId,
          );

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

        final text = utf8.decode(msg.encryptedPayload, allowMalformed: true);
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
                AppRouter.router.go('/chat/${msg.roomId}?peerId=${msg.senderId}&status=ACCEPTED');
              },
            ),
          ),
        );
      });
    });

    // Listen for incoming Chat Request events globally
    ref.listen<AsyncValue<ChatRequest?>>(incomingChatRequestStreamProvider, (prev, next) {
      next.whenData((req) {
        if (req == null) return;
        final chatRepo = ref.read(chatRepositoryProvider);
        final messenger = rootScaffoldMessengerKey.currentState;
        if (messenger == null) return;

        final isRecipient = req.recipientId == chatRepo.currentUserId;
        final isSender = req.senderId == chatRepo.currentUserId;

        if (req.status == ChatRequestStatus.pending && isRecipient) {
          // User B received a new incoming chat request
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.mark_chat_unread_rounded, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Chat Request from ${req.senderDisplayName ?? req.senderUsername ?? "Nearby User"}',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        if (req.senderBio != null && req.senderBio!.isNotEmpty)
                          Text(
                            req.senderBio!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: Colors.white70),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.indigo.shade800,
              duration: const Duration(seconds: 8),
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: 'Accept',
                textColor: Colors.greenAccent,
                onPressed: () async {
                  try {
                    await chatRepo.acceptChatRequest(req.id);
                  } catch (e) {
                    messenger.showSnackBar(SnackBar(content: Text('Failed to accept: $e')));
                  }
                },
              ),
            ),
          );
        } else if (req.status == ChatRequestStatus.accepted && isSender) {
          // User A's request was accepted!
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Chat request accepted by ${req.senderDisplayName ?? "Peer"}! You can now chat.',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.teal.shade900,
              duration: const Duration(seconds: 6),
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: 'Open Chat',
                textColor: Colors.amber,
                onPressed: () {
                  if (req.roomId != null && req.roomId!.isNotEmpty) {
                    AppRouter.router.push('/chat/${req.roomId}?peerId=${req.recipientId}&status=ACCEPTED');
                  }
                },
              ),
            ),
          );
        } else if (req.status == ChatRequestStatus.denied && isSender) {
          // User A's request was denied
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.cancel_rounded, color: Colors.redAccent),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Chat request denied.',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.red.shade900,
              duration: const Duration(seconds: 5),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
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

