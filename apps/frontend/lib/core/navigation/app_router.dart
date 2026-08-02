import 'package:go_router/go_router.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/chat/presentation/chat_screen.dart';
import '../../features/nearby/presentation/nearby_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../network/dio_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppRouter {
  static final authRepo = AuthRepository(
    dioClient: DioClient(),
    secureStorage: const FlutterSecureStorage(),
  );

  static final GoRouter router = GoRouter(
    initialLocation: '/',
    redirect: (context, state) async {
      final isAuth = await authRepo.isAuthenticated();
      final loc = state.matchedLocation;
      final isAuthRoute = loc == '/login' || loc == '/register';

      if (!isAuth && !isAuthRoute) {
        return '/login';
      }
      if (isAuth && isAuthRoute) {
        return '/nearby';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        redirect: (context, state) => '/nearby',
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
          return ChatScreen(roomId: roomId, peerId: peerId);
        },
      ),
    ],
  );
}
