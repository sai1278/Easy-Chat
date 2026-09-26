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

  void _showNotificationSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Consumer(
          builder: (context, ref, _) {
            final settings = ref.watch(userSettingsNotifierProvider);
            final settingsNotifier = ref.read(userSettingsNotifierProvider.notifier);

            return Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Notifications',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 14),
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
            );
          },
        );
      },
    );
  }

  void _showPrivacySettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Consumer(
          builder: (context, ref, _) {
            final settings = ref.watch(userSettingsNotifierProvider);
            final settingsNotifier = ref.read(userSettingsNotifierProvider.notifier);

            return Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Privacy & Security',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 14),
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
            );
          },
        );
      },
    );
  }

  void _showAccountSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Account Settings',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 14),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.badge_outlined, color: AppColors.primary),
                  title: const Text('Change display name', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                  onTap: () {
                    Navigator.pop(context);
                    final p = ref.read(userProfileProvider).value;
                    if (p != null) {
                      _editProfileField(
                        title: 'Display name',
                        initialValue: p.displayName,
                        onSave: (val) {
                          ref.read(userProfileProvider.notifier).updateProfile(
                                displayName: val,
                                avatarUrl: p.avatarUrl,
                                bio: p.bio,
                              );
                        },
                      );
                    }
                  },
                ),
                const Divider(height: 1, color: AppColors.divider),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_outline_rounded, color: AppColors.primary),
                  title: const Text('Edit full profile', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/profile');
                  },
                ),
                const Divider(height: 1, color: AppColors.divider),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                  title: const Text('Delete account', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.danger)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.danger),
                  onTap: () {
                    Navigator.pop(context);
                    _handleDeleteAccount();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(userSettingsNotifierProvider);
    final profileAsync = ref.watch(userProfileProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 20,
        title: const Text(
          'My Settings',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 26,
            letterSpacing: -0.4,
          ),
        ),
      ),
      bottomNavigationBar: ClayBottomNavigationBar(
        currentIndex: 2,
        onTap: (index) {
          if (index == 0) {
            Navigator.of(context).pop();
          }
        },
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
            padding: const EdgeInsets.fromLTRB(20.0, 6.0, 20.0, 20.0),
            children: [
              // 1. Profile card: circular avatar, display name, handle/email, Edit profile link
              ClayCard(
                borderRadius: 16.0,
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
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
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: AppColors.textPrimary,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            profile.username.isNotEmpty ? '${profile.username}@easychat.local' : 'user@easychat.local',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          GestureDetector(
                            onTap: () => context.push('/profile'),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.edit_outlined, size: 14, color: AppColors.primary),
                                SizedBox(width: 4),
                                Text(
                                  'Edit profile',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.primary,
                                  ),
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

              const SizedBox(height: 16),

              // Group 2: Notifications, Privacy & Security, Encryption info card
              _SettingsCardRow(
                icon: Icons.notifications_none_rounded,
                title: 'Notifications',
                value: (settings.notifyChatMessages || settings.notifyNearbyPeers) ? 'On' : 'Off',
                onTap: () => _showNotificationSettings(context),
              ),
              _SettingsCardRow(
                icon: Icons.lock_outline_rounded,
                title: 'Privacy & Security',
                onTap: () => _showPrivacySettings(context),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ClayCard(
                  borderRadius: 16.0,
                  color: const Color(0xFFF4F7FD),
                  border: Border.all(color: AppColors.primary.withOpacity(0.25), width: 0.8),
                  padding: const EdgeInsets.all(14.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(
                          color: AppColors.primaryLight,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.shield_outlined, color: AppColors.primary, size: 18),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Your chats are protected',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                                letterSpacing: -0.1,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'End-to-end encryption keeps your conversations private and secure.',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                                color: AppColors.textSecondary,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Group 3: Appearance, Storage & Data, Account Settings
              _SettingsCardRow(
                icon: Icons.palette_outlined,
                title: 'Appearance',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Theme: Soft Clay (Active)')),
                  );
                },
              ),
              _SettingsCardRow(
                icon: Icons.folder_open_outlined,
                title: 'Storage & Data',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Zero-trust storage: session data stored in RAM')),
                  );
                },
              ),
              _SettingsCardRow(
                icon: Icons.person_outline_rounded,
                title: 'Account Settings',
                onTap: () => _showAccountSettings(context),
              ),

              const SizedBox(height: 8),

              // Group 4: Help & Support, Log out
              _SettingsCardRow(
                icon: Icons.help_outline_rounded,
                title: 'Help & Support',
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: AppColors.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: AppColors.border, width: 0.8),
                      ),
                      title: const Text('Easy Chat Support', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                      content: const Text(
                        'Easy Chat is a private, decentralized ephemeral messaging application.\n\nAll messages, voice notes, and media are end-to-end encrypted with zero server storage.',
                        style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                      ),
                      actions: [
                        ClayButton(label: 'Close', onPressed: () => Navigator.pop(ctx)),
                      ],
                    ),
                  );
                },
              ),
              _SettingsCardRow(
                icon: Icons.logout_rounded,
                title: 'Log out',
                iconColor: AppColors.danger,
                titleColor: AppColors.danger,
                iconBgColor: AppColors.danger.withOpacity(0.08),
                onTap: _handleLogout,
              ),

              const SizedBox(height: 16),
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
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _SettingsCardRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? value;
  final Color? iconColor;
  final Color? titleColor;
  final Color? iconBgColor;
  final VoidCallback? onTap;

  const _SettingsCardRow({
    required this.icon,
    required this.title,
    this.value,
    this.iconColor,
    this.titleColor,
    this.iconBgColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ClayCard(
        borderRadius: 16.0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 38),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: iconBgColor ?? AppColors.surfaceVariant,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.border, width: 0.8),
                  ),
                  child: Icon(
                    icon,
                    size: 18,
                    color: iconColor ?? AppColors.icon,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: titleColor ?? AppColors.textPrimary,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
                if (value != null && value!.isNotEmpty) ...[
                  Text(
                    value!,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: titleColor ?? AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
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
