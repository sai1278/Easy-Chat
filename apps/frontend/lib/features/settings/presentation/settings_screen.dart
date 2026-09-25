import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/clay_design_system.dart';
import '../../auth/data/auth_repository.dart';
import '../../profile/data/profile_repository.dart';
import '../data/settings_repository.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  void _editProfileField({
    required String title,
    required String initialValue,
    required Function(String) onSave,
  }) {
    final controller = TextEditingController(text: initialValue);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.border, width: 0.8),
          ),
          title: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 16,
              color: AppColors.textPrimary,
            ),
          ),
          content: TextField(
            controller: controller,
            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Enter new $title',
              filled: true,
              fillColor: AppColors.background,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.border, width: 0.8),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.border, width: 0.8),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
            ),
            ClayButton(
              label: 'Save',
              onPressed: () {
                onSave(controller.text.trim());
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  void _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border, width: 0.8),
        ),
        title: const Text(
          'Log out',
          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16, color: AppColors.textPrimary),
        ),
        content: const Text(
          'Are you sure you want to log out of Easy Chat?',
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
          ),
          ClayButton(
            label: 'Log out',
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await ref.read(authRepositoryProvider).logout();
      if (mounted) {
        context.go('/login');
      }
    }
  }

  void _handleDeleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border, width: 0.8),
        ),
        title: const Text(
          'Delete account',
          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16, color: AppColors.danger),
        ),
        content: const Text(
          'This action is permanent and will delete your profile data from Easy Chat.',
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete account', style: TextStyle(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account deletion request initiated')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(userSettingsNotifierProvider);
    final settingsNotifier = ref.read(userSettingsNotifierProvider.notifier);
    final profileAsync = ref.watch(userProfileProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border, width: 0.8),
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded, size: 14, color: AppColors.icon),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Settings',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w500,
            fontSize: 18,
            letterSpacing: -0.2,
          ),
        ),
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
          child: Text('Error loading settings: $err', style: const TextStyle(color: AppColors.textSecondary)),
        ),
        data: (profile) {
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            children: [
              // 1. Profile card at the top: avatar, display name, handle, outlined Edit button
              ClayCard(
                borderRadius: 12.0,
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceVariant,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.border, width: 0.8),
                          ),
                          child: ClipOval(
                            child: profile.avatarUrl.isNotEmpty
                                ? Image.network(
                                    profile.avatarUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => _buildAvatarInitial(profile),
                                  )
                                : _buildAvatarInitial(profile),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                profile.displayName.isNotEmpty ? profile.displayName : profile.username,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 16,
                                  color: AppColors.textPrimary,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '@${profile.username}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ClaySecondaryButton(
                          label: 'Edit',
                          icon: Icons.edit_outlined,
                          onPressed: () => context.push('/profile'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Divider(height: 1, color: AppColors.divider),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.badge_outlined, color: AppColors.icon, size: 20),
                      title: const Text(
                        'Display name',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
                      ),
                      subtitle: Text(
                        profile.displayName.isNotEmpty ? profile.displayName : 'Not set',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.textSecondary),
                      ),
                      onTap: () => _editProfileField(
                        title: 'Display name',
                        initialValue: profile.displayName,
                        onSave: (val) {
                          ref.read(userProfileProvider.notifier).updateProfile(
                                displayName: val,
                                avatarUrl: profile.avatarUrl,
                                bio: profile.bio,
                              );
                        },
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.info_outline_rounded, color: AppColors.icon, size: 20),
                      title: const Text(
                        'Bio',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
                      ),
                      subtitle: Text(
                        profile.bio.isNotEmpty ? profile.bio : 'No bio added',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.textSecondary),
                      ),
                      onTap: () => _editProfileField(
                        title: 'Bio',
                        initialValue: profile.bio,
                        onSave: (val) {
                          ref.read(userProfileProvider.notifier).updateProfile(
                                displayName: profile.displayName,
                                avatarUrl: profile.avatarUrl,
                                bio: val,
                              );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 2. Privacy and visibility: Card containing two toggle rows
              const _SectionHeader(title: 'Privacy and visibility', icon: Icons.visibility_outlined),
              ClayCard(
                borderRadius: 12.0,
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    _ToggleRow(
                      icon: Icons.radar_rounded,
                      title: 'Discoverable nearby',
                      description: 'Allow nearby people to discover your profile within 1 km',
                      value: settings.discoverable,
                      onChanged: (val) => settingsNotifier.toggleDiscoverable(val),
                    ),
                    const Divider(height: 1, color: AppColors.divider),
                    _ToggleRow(
                      icon: Icons.lock_outline_rounded,
                      title: 'Secure local storage',
                      description: 'Keep your conversations encrypted on device',
                      value: settings.encryptLocalSessions,
                      onChanged: (val) => settingsNotifier.toggleEncryptSessions(val),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 3. Notifications: Card containing two toggle rows
              const _SectionHeader(title: 'Notifications', icon: Icons.notifications_outlined),
              ClayCard(
                borderRadius: 12.0,
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    _ToggleRow(
                      icon: Icons.sensors_rounded,
                      title: 'Nearby alerts',
                      description: 'Get notified when someone enters your nearby area',
                      value: settings.notifyNearbyPeers,
                      onChanged: (val) => settingsNotifier.toggleNotifyNearby(val),
                    ),
                    const Divider(height: 1, color: AppColors.divider),
                    _ToggleRow(
                      icon: Icons.chat_bubble_outline_rounded,
                      title: 'Chat notifications',
                      description: 'Receive alerts for incoming messages',
                      value: settings.notifyChatMessages,
                      onChanged: (val) => settingsNotifier.toggleNotifyChat(val),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 4. About Easy Chat
              const _SectionHeader(title: 'About Easy Chat', icon: Icons.info_outline_rounded),
              ClayCard(
                borderRadius: 12.0,
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border, width: 0.8),
                      ),
                      padding: const EdgeInsets.all(6),
                      child: const EasyChatLogoMark(size: 28),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Easy chat',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Private, ephemeral nearby messaging',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const ClayBadge(label: 'v1.0.0'),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // 5. Account Actions Section
              ClaySecondaryButton(
                label: 'Log out',
                icon: Icons.logout_rounded,
                onPressed: _handleLogout,
              ),
              const SizedBox(height: 10),
              Center(
                child: TextButton.icon(
                  onPressed: _handleDeleteAccount,
                  icon: const Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.danger),
                  label: const Text(
                    'Delete account',
                    style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w500, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
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
          fontSize: 20,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.icon),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: AppColors.icon, size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          AppToggle(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
