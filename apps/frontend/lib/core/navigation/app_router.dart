import 'package:go_router/go_router.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/chat/presentation/chat_screen.dart';
import '../../features/chat/domain/chat_request.dart';
import '../../features/nearby/presentation/nearby_screen.dart';
import '../../features/onboarding/presentation/splash_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../network/dio_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppRouter {
  static final authRepo = AuthRepository(
    dioClient: DioClient(),
    secureStorage: const FlutterSecureStorage(),
  );

  static final GoRouter router = GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) async {
      final isAuth = await authRepo.isAuthenticated();
      final loc = state.matchedLocation;
      final isBypassRoute = loc == '/splash' || loc == '/onboarding' || loc == '/login' || loc == '/register';

      if (!isAuth && !isBypassRoute) {
        return '/login';
      }
      if (isAuth && (loc == '/login' || loc == '/register')) {
        return '/nearby';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        redirect: (context, state) => '/splash',
      ),
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/nearby',
        builder: (context, state) => const NearbyScreen(),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/chat/:roomId',
        builder: (context, state) {
          final roomId = state.pathParameters['roomId'] ?? '';
          final peerId = state.uri.queryParameters['peerId'] ?? '';
          final statusStr = state.uri.queryParameters['status'];
          final initialStatus = statusStr != null && statusStr.isNotEmpty
              ? ChatRequestStatus.fromString(statusStr)
              : ChatRequestStatus.accepted;
          return ChatScreen(roomId: roomId, peerId: peerId, initialStatus: initialStatus);
        },
      ),
    ],
  );
}
