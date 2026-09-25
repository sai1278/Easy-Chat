import 'dart:async';
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
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.96, end: 1.02).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOutCubic),
    );

    _fadeAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(
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
        body: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 3),
              // Centered vertically as one group: [logo], "Easy chat", "Connect with people nearby"
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return ScaleTransition(
                    scale: _scaleAnimation,
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          color: const Color(0xFF030508),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: AppColors.border, width: 0.8),
                        ),
                        child: const Center(
                          child: EasyChatLogoMark(size: 54),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              const Text(
                'Easy chat',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Connect with people nearby',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textSecondary,
                  letterSpacing: -0.1,
                ),
              ),
              const Spacer(flex: 4),
              // At bottom: three small blue loading dots (#3B6FE0)
              const _ThreeBlueLoadingDots(),
              const SizedBox(height: 32),
            ],
          ),
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
      duration: const Duration(milliseconds: 1000),
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
            final shift = (index * 0.25);
            final t = (_controller.value + shift) % 1.0;
            final opacity = (0.3 + 0.7 * (1.0 - (2 * (t - 0.5)).abs())).clamp(0.3, 1.0);

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 7,
              height: 7,
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
