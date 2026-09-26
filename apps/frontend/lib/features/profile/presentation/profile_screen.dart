import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
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
            backgroundColor: AppColors.success,
          ),
        );
      }
    } on ProfileException catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: AppColors.danger,
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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leadingWidth: 54,
        leading: Center(
          child: ClayCircleButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onPressed: () => Navigator.of(context).pop(),
            size: 38,
            iconSize: 15,
          ),
        ),
        title: const Text(
          'Edit Profile',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 18,
            letterSpacing: -0.2,
          ),
        ),
        actions: [
          ClayCircleButton(
            icon: Icons.refresh_rounded,
            onPressed: () => ref.read(userProfileProvider.notifier).loadProfile(),
            size: 38,
            iconSize: 18,
            iconColor: AppColors.icon,
            tooltip: 'Refresh Profile',
          ),
          const SizedBox(width: 14),
        ],
      ),
      body: profileAsync.when(
        loading: () => const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
          ),
        ),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: ClayCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.danger),
                  const SizedBox(height: 16),
                  const Text(
                    'Failed to load profile',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 8),
                  Text('$err', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
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
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  // Tactile Clay Avatar Header
                  Center(
                    child: Stack(
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.border, width: 1.5),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x0A1F2328),
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
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
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.background, width: 2),
                            ),
                            child: const Icon(Icons.camera_alt_rounded, size: 14, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '@${profile.username}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.primary),
                  ),
                  const SizedBox(height: 20),

                  // Form Fields Clay Card
                  ClayCard(
                    borderRadius: 18.0,
                    padding: const EdgeInsets.all(18.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Profile Details',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _displayNameController,
                          style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            labelText: 'Display Name',
                            labelStyle: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                            prefixIcon: const Icon(Icons.person_outline_rounded, color: AppColors.icon, size: 20),
                            hintText: 'Enter your name',
                            hintStyle: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                            filled: true,
                            fillColor: AppColors.background,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppColors.border, width: 0.8),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppColors.border, width: 0.8),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                            ),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'Display name cannot be empty';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _avatarUrlController,
                          style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            labelText: 'Avatar Image URL (Optional)',
                            labelStyle: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                            prefixIcon: const Icon(Icons.link_rounded, color: AppColors.icon, size: 20),
                            hintText: 'https://example.com/avatar.jpg',
                            hintStyle: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                            filled: true,
                            fillColor: AppColors.background,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppColors.border, width: 0.8),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppColors.border, width: 0.8),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _bioController,
                          maxLines: 3,
                          style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            labelText: 'About You',
                            labelStyle: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                            prefixIcon: const Icon(Icons.info_outline_rounded, color: AppColors.icon, size: 20),
                            hintText: 'Share a short bio with people nearby...',
                            hintStyle: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                            filled: true,
                            fillColor: AppColors.background,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppColors.border, width: 0.8),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppColors.border, width: 0.8),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                            ),
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
        style: const TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
      ),
    );
  }
}
