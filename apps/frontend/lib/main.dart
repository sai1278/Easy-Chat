import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'core/database/isar_service.dart';
import 'core/navigation/app_router.dart';
import 'core/network/dio_client.dart';
import 'core/network/websocket_client.dart';
import 'core/utils/battery_optimizer.dart';
import 'features/chat/data/chat_repository.dart';
import 'features/chat/presentation/chat_controller.dart';
import 'features/nearby/presentation/nearby_screen.dart';
import 'features/nearby/domain/proximity_user.dart';

final webSocketClientProvider = Provider<WebSocketClient>((ref) => throw UnimplementedError());

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
        final normalized = base64Url.normalize(parts[1]);
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
        // Override repository provider with initialized instance
        chatRepositoryProvider.overrideWith((ref) {
          final repo = ChatRepository(
            isar: isarService.isar,
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _batteryOptimizer.start();
      ref.read(chatRepositoryProvider);
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

    // 4. Bind root router to GoRouter declarative navigator
    return MaterialApp.router(
      title: 'Nearby Connect',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      routerConfig: AppRouter.router,
      debugShowCheckedModeBanner: false,
    );
  }
}
