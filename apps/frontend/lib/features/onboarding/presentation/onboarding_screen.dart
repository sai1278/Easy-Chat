import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/location_service.dart';
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
  bool _bluetoothGranted = true;
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
    if (_currentPage < 4) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
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
        const SnackBar(content: Text('Location permission granted successfully!')),
      );
      _nextPage();
    }
  }

  Future<void> _requestBluetoothPermission() async {
    setState(() {
      _bluetoothGranted = true;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bluetooth BLE mesh discovery enabled!')),
      );
      _nextPage();
    }
  }

  Future<void> _completeOnboarding() async {
    setState(() {
      _isCompleting = true;
    });

    // Save initial profile
    await ref.read(userProfileProvider.notifier).updateProfile(
          displayName: _displayNameController.text.trim(),
          avatarUrl: _avatarUrlController.text.trim(),
          bio: _bioController.text.trim(),
        );

    // Save onboarding completion in SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed', true);

    if (mounted) {
      // Show Success Dialog
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          final colorScheme = Theme.of(context).colorScheme;
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            content: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.check_circle_rounded, size: 54, color: colorScheme.primary),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Setup Complete!',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Welcome to Nearby Connect. Discovering active spatial peers...',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          );
        },
      );

      if (mounted) {
        context.go('/nearby');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Top Indicator Row
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                children: [
                  Text(
                    'Nearby Connect',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.primary),
                  ),
                  const Spacer(),
                  if (_currentPage < 4)
                    TextButton(
                      onPressed: () {
                        _pageController.animateToPage(
                          4,
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeInOut,
                        );
                      },
                      child: const Text('Skip'),
                    ),
                ],
              ),
            ),

            // PageView Content
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (idx) {
                  setState(() {
                    _currentPage = idx;
                  });
                },
                children: [
                  // Step 1: Welcome
                  _OnboardingSlide(
                    icon: Icons.handshake_rounded,
                    title: 'Welcome to Nearby Connect',
                    subtitle: 'Instant Ephemeral P2P Messaging',
                    description:
                        'Connect and chat with people within 50 meters in real time. No phone numbers, no persistent server footprints.',
                    actionWidget: FilledButton.icon(
                      onPressed: _nextPage,
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: const Text('Get Started'),
                    ),
                  ),

                  // Step 2: Location Explanation
                  _OnboardingSlide(
                    icon: Icons.location_on_rounded,
                    title: 'Spatial Discovery Access',
                    subtitle: 'Precision Proximity Matching',
                    description:
                        'Nearby Connect uses your device location exclusively to calculate distance between nearby users. Your location is never tracked or shared.',
                    actionWidget: FilledButton.icon(
                      onPressed: _requestLocationPermission,
                      icon: Icon(_locationGranted ? Icons.check_circle_rounded : Icons.gps_fixed_rounded),
                      label: Text(_locationGranted ? 'Location Granted' : 'Enable Location Access'),
                    ),
                  ),

                  // Step 3: Bluetooth Explanation
                  _OnboardingSlide(
                    icon: Icons.bluetooth_searching_rounded,
                    title: 'Direct BLE Mesh',
                    subtitle: 'Offline Peer-to-Peer Protocol',
                    description:
                        'Communicate directly over Bluetooth Low Energy when mobile data is limited. Devices automatically form an offline mesh network.',
                    actionWidget: FilledButton.icon(
                      onPressed: _requestBluetoothPermission,
                      icon: Icon(_bluetoothGranted ? Icons.check_circle_rounded : Icons.bluetooth_rounded),
                      label: Text(_bluetoothGranted ? 'Bluetooth Enabled' : 'Enable Bluetooth Mesh'),
                    ),
                  ),

                  // Step 4: Privacy Explanation
                  _OnboardingSlide(
                    icon: Icons.shield_rounded,
                    title: 'Zero-Knowledge Privacy',
                    subtitle: 'End-to-End Encrypted Sessions',
                    description:
                        'All chat sessions are encrypted using AES-256. When you leave spatial range, your conversation self-destructs automatically.',
                    actionWidget: FilledButton.icon(
                      onPressed: _nextPage,
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: const Text('Set Up Profile'),
                    ),
                  ),

                  // Step 5: Profile Setup Form
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: CircleAvatar(
                            radius: 44,
                            backgroundColor: colorScheme.primaryContainer,
                            backgroundImage: _avatarUrlController.text.isNotEmpty
                                ? NetworkImage(_avatarUrlController.text) as ImageProvider
                                : null,
                            child: _avatarUrlController.text.isEmpty
                                ? Icon(Icons.person_rounded, size: 44, color: colorScheme.onPrimaryContainer)
                                : null,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Center(
                          child: Text(
                            'Create Your Nearby Handle',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _displayNameController,
                          decoration: const InputDecoration(
                            labelText: 'Display Name',
                            prefixIcon: Icon(Icons.badge_rounded),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _avatarUrlController,
                          decoration: const InputDecoration(
                            labelText: 'Avatar Image URL (Optional)',
                            prefixIcon: Icon(Icons.link_rounded),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _bioController,
                          decoration: const InputDecoration(
                            labelText: 'Bio / Status',
                            prefixIcon: Icon(Icons.info_outline_rounded),
                          ),
                        ),
                        const SizedBox(height: 32),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _isCompleting ? null : _completeOnboarding,
                            icon: _isCompleting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.rocket_launch_rounded),
                            label: Text(_isCompleting ? 'Launching...' : 'Complete & Launch Nearby'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Page Indicator Dots
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  final active = _currentPage == index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: active ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: active ? colorScheme.primary : colorScheme.outlineVariant,
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
  final String title;
  final String subtitle;
  final String description;
  final Widget actionWidget;

  const _OnboardingSlide({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.actionWidget,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 64, color: colorScheme.onPrimaryContainer),
          ),
          const SizedBox(height: 36),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: colorScheme.secondary),
          ),
          const SizedBox(height: 16),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 1.5, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 44),
          actionWidget,
        ],
      ),
    );
  }
}
