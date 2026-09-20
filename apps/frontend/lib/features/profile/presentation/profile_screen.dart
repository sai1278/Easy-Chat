import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/clay_design_system.dart';
import '../data/profile_repository.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _displayNameController;
  late TextEditingController _avatarUrlController;
  late TextEditingController _bioController;
  bool _isSaving = false;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController();
    _avatarUrlController = TextEditingController();
    _bioController = TextEditingController();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _avatarUrlController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
    });

    try {
      await ref.read(userProfileProvider.notifier).updateProfile(
            displayName: _displayNameController.text.trim(),
            avatarUrl: _avatarUrlController.text.trim(),
            bio: _bioController.text.trim(),
          );

      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully!'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    } on ProfileException catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: const Color(0xFFDC2626),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unexpected error: $e'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(userProfileProvider);

    return Scaffold(
      backgroundColor: ClayColors.background,
      appBar: AppBar(
        backgroundColor: ClayColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: ClayColors.cardSurface,
              shape: BoxShape.circle,
              boxShadow: ClayShadows.button,
            ),
            child: Icon(Icons.arrow_back_ios_new_rounded, size: 14, color: ClayColors.textPrimary),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Profile',
          style: TextStyle(
            color: ClayColors.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 20,
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: ClayColors.cardSurface,
                shape: BoxShape.circle,
                boxShadow: ClayShadows.button,
              ),
              child: Icon(Icons.refresh_rounded, size: 18, color: ClayColors.textSecondary),
            ),
            tooltip: 'Refresh Profile',
            onPressed: () => ref.read(userProfileProvider.notifier).loadProfile(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: profileAsync.when(
        loading: () => Center(
          child: CircularProgressIndicator(color: ClayColors.accent),
        ),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: ClayCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline_rounded, size: 48, color: const Color(0xFFDC2626)),
                  const SizedBox(height: 16),
                  Text(
                    'Failed to load profile',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: ClayColors.textPrimary),
                  ),
                  const SizedBox(height: 8),
                  Text('$err', style: TextStyle(color: ClayColors.textSecondary, fontSize: 13)),
                  const SizedBox(height: 16),
                  ClayButton(
                    label: 'Retry',
                    icon: Icons.refresh,
                    onPressed: () => ref.read(userProfileProvider.notifier).loadProfile(),
                  ),
                ],
              ),
            ),
          ),
        ),
        data: (profile) {
          if (!_initialized) {
            _displayNameController.text = profile.displayName.isNotEmpty ? profile.displayName : profile.username;
            _avatarUrlController.text = profile.avatarUrl;
            _bioController.text = profile.bio;
            _initialized = true;
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  // Tactile Clay Avatar Header
                  Center(
                    child: Stack(
                      children: [
                        Container(
                          width: 104,
                          height: 104,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: ClayShadows.card,
                            border: Border.all(color: ClayColors.borderSubtle, width: 2),
                          ),
                          child: ClipOval(
                            child: _avatarUrlController.text.isNotEmpty
                                ? Image.network(
                                    _avatarUrlController.text,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => _buildAvatarInitial(profile),
                                  )
                                : _buildAvatarInitial(profile),
                          ),
                        ),
                        Positioned(
                          right: 2,
                          bottom: 2,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: ClayColors.accent,
                              shape: BoxShape.circle,
                              boxShadow: ClayShadows.button,
                            ),
                            child: const Icon(Icons.camera_alt_rounded, size: 16, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '@${profile.username}',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ClayColors.accent),
                  ),
                  const SizedBox(height: 20),

                  // Form Fields Clay Card
                  ClayCard(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Profile Details',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: ClayColors.textPrimary,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _displayNameController,
                          decoration: const InputDecoration(
                            labelText: 'Display Name',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                            hintText: 'Enter your name',
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'Display name cannot be empty';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _avatarUrlController,
                          decoration: const InputDecoration(
                            labelText: 'Avatar Image URL (Optional)',
                            prefixIcon: Icon(Icons.link_rounded),
                            hintText: 'https://example.com/avatar.jpg',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _bioController,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'About You',
                            prefixIcon: Icon(Icons.info_outline_rounded),
                            hintText: 'Share a short bio with people nearby...',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  ClayButton(
                    label: _isSaving ? 'Saving Profile...' : 'Save Profile',
                    icon: _isSaving ? null : Icons.check_rounded,
                    isLoading: _isSaving,
                    onPressed: _isSaving ? null : _saveProfile,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAvatarInitial(profile) {
    return Center(
      child: Text(
        profile.displayName.isNotEmpty
            ? profile.displayName[0].toUpperCase()
            : (profile.username.isNotEmpty ? profile.username[0].toUpperCase() : 'U'),
        style: TextStyle(
          fontSize: 38,
          fontWeight: FontWeight.w800,
          color: ClayColors.accent,
        ),
      ),
    );
  }
}
