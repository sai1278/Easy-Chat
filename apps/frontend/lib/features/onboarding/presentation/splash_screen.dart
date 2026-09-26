import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../auth/data/auth_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/clay_design_system.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.985, end: 1.015).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOutCubic),
    );

    _fadeAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _navigateNext();
  }

  Future<void> _navigateNext() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final completed = prefs.getBool('onboarding_completed') ?? false;
    final isAuth = await ref.read(authRepositoryProvider).isAuthenticated();

    if (!mounted) return;

    if (!completed) {
      context.go('/onboarding');
    } else if (isAuth) {
      context.go('/nearby');
    } else {
      context.go('/login');
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: AppColors.background,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.background,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          children: [
            // Background organic clay wave curves in corners
            const Positioned.fill(
              child: CustomPaint(
                painter: OrganicClayBackgroundPainter(),
              ),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // 1. Tactile Clay Logo Tile (Squircle with multi-layered clay elevation)
                        AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, child) {
                            return Transform.scale(
                              scale: _scaleAnimation.value,
                              child: FadeTransition(
                                opacity: _fadeAnimation,
                                child: child,
                              ),
                            );
                          },
                          child: Container(
                            width: 136,
                            height: 136,
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(36),
                              border: Border.all(
                                color: AppColors.border.withOpacity(0.6),
                                width: 0.8,
                              ),
                              boxShadow: const [
                                // Soft ambient drop shadow
                                BoxShadow(
                                  color: Color(0x0E1F2328),
                                  offset: Offset(0, 16),
                                  blurRadius: 32,
                                  spreadRadius: 0,
                                ),
                                // Close contact shadow for physical grounding
                                BoxShadow(
                                  color: Color(0x061F2328),
                                  offset: Offset(0, 4),
                                  blurRadius: 10,
                                  spreadRadius: 0,
                                ),
                                // Subtle top highlight for soft molded clay elevation
                                BoxShadow(
                                  color: Colors.white,
                                  offset: Offset(0, -2),
                                  blurRadius: 4,
                                  spreadRadius: 0,
                                ),
                              ],
                            ),
                            child: Center(
                              child: Container(
                                width: 66,
                                height: 66,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(18),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x1A000000),
                                      offset: Offset(0, 3),
                                      blurRadius: 6,
                                    ),
                                  ],
                                ),
                                child: const EasyChatLogoMark(size: 66),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 28),

                        // 2. Title: "Easy chat"
                        const Text(
                          'Easy chat',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.4,
                          ),
                        ),

                        const SizedBox(height: 8),

                        // 3. Subtitle: "Connect with people nearby"
                        const Text(
                          'Connect with people nearby',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w400,
                            color: AppColors.textSecondary,
                            letterSpacing: -0.1,
                            height: 1.3,
                          ),
                        ),

                        const SizedBox(height: 36),

                        // 4. Three blue loading dots
                        const _ThreeBlueLoadingDots(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Three small blue loading dots (#3B6FE0) with smooth staggered pulse
class _ThreeBlueLoadingDots extends StatefulWidget {
  const _ThreeBlueLoadingDots();

  @override
  State<_ThreeBlueLoadingDots> createState() => _ThreeBlueLoadingDotsState();
}

class _ThreeBlueLoadingDotsState extends State<_ThreeBlueLoadingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (index) {
            final shift = index * 0.22;
            final t = (_controller.value + shift) % 1.0;
            final wave = 0.5 - 0.5 * math.cos(t * 2 * math.pi);
            final opacity = (0.28 + 0.72 * wave).clamp(0.28, 1.0);
            final scale = 0.88 + 0.24 * wave;

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 3.5),
              width: 6.5,
              height: 6.5,
              transform: Matrix4.diagonal3Values(scale, scale, 1.0),
              transformAlignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withOpacity(opacity),
              ),
            );
          }),
        );
      },
    );
  }
}
