import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/location_service.dart';
import '../../../core/theme/clay_design_system.dart';
import '../../auth/data/auth_repository.dart';
import '../../profile/data/profile_repository.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final TextEditingController _displayNameController = TextEditingController(text: 'Proximity User');
  final TextEditingController _avatarUrlController = TextEditingController();
  final TextEditingController _bioController = TextEditingController(text: 'Exploring nearby spatial chat');

  bool _locationGranted = false;
  bool _isCompleting = false;

  @override
  void dispose() {
    _pageController.dispose();
    _displayNameController.dispose();
    _avatarUrlController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < 3) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _requestLocationPermission() async {
    final locationService = ref.read(locationServiceProvider);
    final granted = await locationService.checkAndRequestPermission();
    setState(() {
      _locationGranted = granted;
    });

    if (granted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location access granted.')),
      );
      _nextPage();
    }
  }

  Future<void> _completeOnboarding() async {
    if (_isCompleting) return;

    dev.log('[ONBOARDING][01] _completeOnboarding() entered', name: 'OnboardingTrace');
    setState(() => _isCompleting = true);

    try {
      final authRepo = ref.read(authRepositoryProvider);
      final isAuth = await authRepo.isAuthenticated();
      if (!isAuth) {
        dev.log('[ONBOARDING][01-AUTH] Registering and logging in device session...', name: 'OnboardingTrace');
        await authRepo.registerAndLogin('NearbyPass123!');
        ref.invalidate(authStateProvider);
      }

      dev.log('[ONBOARDING][02] Saving user profile...', name: 'OnboardingTrace');
      await ref.read(userProfileProvider.notifier).updateProfile(
            displayName: _displayNameController.text.trim(),
            avatarUrl: _avatarUrlController.text.trim(),
            bio: _bioController.text.trim(),
          );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarding_completed', true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Welcome to Easy Chat!'),
            backgroundColor: ClayColors.accent,
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      await Future.delayed(const Duration(milliseconds: 400));

      if (mounted) {
        context.go('/nearby');
      }
    } on ProfileException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: ClayColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e, stack) {
      dev.log('[ONBOARDING][ERR] Unexpected: $e\n$stack', name: 'OnboardingTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to complete setup: $e'),
            backgroundColor: ClayColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCompleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ClayColors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Row(
                children: [
                  const EasyChatLogoMark(size: 32),
                  const SizedBox(width: 10),
                  const Text(
                    'Easy Chat',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: ClayColors.textPrimary,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const Spacer(),
                  if (_currentPage < 3)
                    TextButton(
                      onPressed: () {
                        _pageController.animateToPage(
                          3,
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeOutCubic,
                        );
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: ClayColors.textSecondary,
                        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      child: const Text('Skip'),
                    ),
                ],
              ),
            ),

            // Slides Content
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (idx) => setState(() => _currentPage = idx),
                children: [
                  // Step 1: Discover
                  _OnboardingSlide(
                    icon: Icons.radar_rounded,
                    stepTag: 'DISCOVER',
                    title: 'Find People Nearby',
                    description: 'Discover other users around you in real time within 1 km. No phone numbers or handles needed.',
                    actionButton: ClayButton(
                      label: _locationGranted ? 'Continue' : 'Enable Location',
                      icon: Icons.location_on_rounded,
                      onPressed: _locationGranted ? _nextPage : _requestLocationPermission,
                    ),
                  ),

                  // Step 2: Connect
                  _OnboardingSlide(
                    icon: Icons.chat_bubble_outline_rounded,
                    stepTag: 'CONNECT',
                    title: 'Send Private Requests',
                    description: 'Chat only begins when both users agree. Tap to connect and accept incoming invitations instantly.',
                    actionButton: ClayButton(
                      label: 'Continue',
                      icon: Icons.arrow_forward_rounded,
                      onPressed: _nextPage,
                    ),
                  ),

                  // Step 3: Chat
                  _OnboardingSlide(
                    icon: Icons.lock_outline_rounded,
                    stepTag: 'CHAT',
                    title: 'Ephemeral & Private',
                    description: 'Conversations are direct and private. Messages leave no permanent trace when you move away.',
                    actionButton: ClayButton(
                      label: 'Set Up Profile',
                      icon: Icons.person_outline_rounded,
                      onPressed: _nextPage,
                    ),
                  ),

                  // Step 4: Profile Creation Form
                  SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                    child: Column(
                      children: [
                        const SizedBox(height: 12),
                        ClayCard(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Center(
                                child: Stack(
                                  children: [
                                    Container(
                                      width: 90,
                                      height: 90,
                                      decoration: BoxDecoration(
                                        color: ClayColors.surfaceMuted,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: ClayColors.borderSoft, width: 2),
                                      ),
                                      child: _avatarUrlController.text.isNotEmpty
                                          ? ClipOval(
                                              child: Image.network(
                                                _avatarUrlController.text,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded, size: 48, color: ClayColors.textSecondary),
                                              ),
                                            )
                                          : const Icon(Icons.person_rounded, size: 48, color: ClayColors.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                              const Text(
                                'Create Your Profile',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: ClayColors.textPrimary,
                                  letterSpacing: -0.4,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Visible only to users within 1 km',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: ClayColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 24),
                              TextFormField(
                                controller: _displayNameController,
                                decoration: const InputDecoration(
                                  labelText: 'Display Name',
                                  hintText: 'e.g. Alex',
                                  prefixIcon: Icon(Icons.badge_outlined, color: ClayColors.textSecondary),
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _bioController,
                                decoration: const InputDecoration(
                                  labelText: 'Status / Bio',
                                  hintText: 'e.g. Exploring nearby spatial chat',
                                  prefixIcon: Icon(Icons.edit_note_rounded, color: ClayColors.textSecondary),
                                ),
                              ),
                              const SizedBox(height: 28),
                              ClayButton(
                                label: _isCompleting ? 'Starting...' : 'Start Chatting',
                                icon: Icons.bolt_rounded,
                                isLoading: _isCompleting,
                                onPressed: _isCompleting ? null : _completeOnboarding,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Page Indicator
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  final active = _currentPage == index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: active ? 22 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: active ? ClayColors.accent : ClayColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingSlide extends StatelessWidget {
  final IconData icon;
  final String stepTag;
  final String title;
  final String description;
  final Widget actionButton;

  const _OnboardingSlide({
    required this.icon,
    required this.stepTag,
    required this.title,
    required this.description,
    required this.actionButton,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Elevated Clay Icon Container
          ClayCard(
            borderRadius: 36,
            padding: const EdgeInsets.all(32),
            child: Icon(icon, size: 56, color: ClayColors.accent),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: ClayColors.accentLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              stepTag,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: ClayColors.accent,
                letterSpacing: 1.0,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: ClayColors.textPrimary,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                height: 1.5,
                color: ClayColors.textSecondary,
                letterSpacing: -0.2,
              ),
            ),
          ),
          const SizedBox(height: 40),
          actionButton,
        ],
      ),
    );
  }
}
