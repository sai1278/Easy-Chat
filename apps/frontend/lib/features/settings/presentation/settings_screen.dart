import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: 'Enter new $title',
              filled: true,
              fillColor: colorScheme.surfaceContainerHigh,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                onSave(controller.text.trim());
                Navigator.pop(context);
              },
              child: const Text('Save'),
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
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out of Nearby Connect? Local sessions will be cleared.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Log Out')),
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
    final colorScheme = Theme.of(context).colorScheme;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Account', style: TextStyle(color: colorScheme.error)),
        content: const Text('This action is permanent and will wipe all your profile data and active keys.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete Account'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account deletion request initiated.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(userSettingsNotifierProvider);
    final settingsNotifier = ref.read(userSettingsNotifierProvider.notifier);
    final profileAsync = ref.watch(userProfileProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: profileAsync.when(
        loading: () => Center(child: CircularProgressIndicator(color: colorScheme.primary)),
        error: (err, _) => Center(child: Text('Error loading profile settings: $err')),
        data: (profile) {
          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              // User Profile Section Card
              Card(
                color: colorScheme.surfaceContainerLow,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.4)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: colorScheme.primaryContainer,
                            backgroundImage: profile.avatarUrl.isNotEmpty ? NetworkImage(profile.avatarUrl) : null,
                            child: profile.avatarUrl.isEmpty
                                ? Text(
                                    profile.displayName.isNotEmpty ? profile.displayName[0].toUpperCase() : 'U',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onPrimaryContainer,
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  profile.displayName.isNotEmpty ? profile.displayName : profile.username,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                                ),
                                Text(
                                  '@${profile.username}',
                                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => context.push('/profile'),
                            icon: const Icon(Icons.edit_rounded, size: 16),
                            label: const Text('Edit'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Divider(color: colorScheme.outlineVariant.withOpacity(0.4)),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.badge_rounded),
                        title: const Text('Display Name'),
                        subtitle: Text(profile.displayName.isNotEmpty ? profile.displayName : 'Not set'),
                        onTap: () => _editProfileField(
                          title: 'Display Name',
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
                        leading: const Icon(Icons.alternate_email_rounded),
                        title: const Text('Username'),
                        subtitle: Text('@${profile.username}'),
                        onTap: () => _editProfileField(
                          title: 'Username',
                          initialValue: profile.username,
                          onSave: (val) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Username updated successfully.')),
                            );
                          },
                        ),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.info_outline_rounded),
                        title: const Text('Bio / Status'),
                        subtitle: Text(profile.bio.isNotEmpty ? profile.bio : 'No bio added'),
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
              ),
              const SizedBox(height: 16),

              // Spatial Privacy & Discovery Section
              const _SectionHeader(title: 'Privacy & Spatial Visibility', icon: Icons.visibility_rounded),
              Card(
                color: colorScheme.surfaceContainerLow,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.4)),
                ),
                child: Column(
                  children: [
                    SwitchListTile(
                      value: settings.discoverable,
                      onChanged: (val) => settingsNotifier.toggleDiscoverable(val),
                      title: const Text('Discoverable Nearby'),
                      subtitle: const Text('Allow nearby Bluetooth & GPS devices to discover your peer handle.'),
                      secondary: const Icon(Icons.radar_rounded),
                    ),
                    Divider(height: 1, color: colorScheme.outlineVariant.withOpacity(0.3)),
                    SwitchListTile(
                      value: settings.encryptLocalSessions,
                      onChanged: (val) => settingsNotifier.toggleEncryptSessions(val),
                      title: const Text('Local Session Encryption'),
                      subtitle: const Text('Encrypt local Isar message cache with AES-GCM 256-bit key.'),
                      secondary: const Icon(Icons.lock_rounded),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Notifications Section
              const _SectionHeader(title: 'Notifications & Alerts', icon: Icons.notifications_rounded),
              Card(
                color: colorScheme.surfaceContainerLow,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.4)),
                ),
                child: Column(
                  children: [
                    SwitchListTile(
                      value: settings.notifyNearbyPeers,
                      onChanged: (val) => settingsNotifier.toggleNotifyNearby(val),
                      title: const Text('Nearby Peer Proximity Alerts'),
                      subtitle: const Text('Notify when a new active peer enters 50m spatial radius.'),
                      secondary: const Icon(Icons.sensors_rounded),
                    ),
                    Divider(height: 1, color: colorScheme.outlineVariant.withOpacity(0.3)),
                    SwitchListTile(
                      value: settings.notifyChatMessages,
                      onChanged: (val) => settingsNotifier.toggleNotifyChat(val),
                      title: const Text('Chat Messages'),
                      subtitle: const Text('Receive vibrate and sound notifications for incoming messages.'),
                      secondary: const Icon(Icons.chat_bubble_rounded),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // About Nearby Connect Section
              const _SectionHeader(title: 'About Nearby Connect', icon: Icons.info_rounded),
              Card(
                color: colorScheme.surfaceContainerLow,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.4)),
                ),
                child: Column(
                  children: [
                    const ListTile(
                      leading: Icon(Icons.verified_rounded),
                      title: Text('App Version'),
                      trailing: Text('v1.0.0+1', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    Divider(height: 1, color: colorScheme.outlineVariant.withOpacity(0.3)),
                    const ListTile(
                      leading: Icon(Icons.memory_rounded),
                      title: Text('Architecture'),
                      subtitle: Text('Flutter 3.x • Go Microservices • P2P BLE Mesh • Redis GEO'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Account Actions Section
              OutlinedButton.icon(
                onPressed: _handleLogout,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Log Out'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _handleDeleteAccount,
                icon: Icon(Icons.delete_forever_rounded, color: colorScheme.error),
                label: Text('Delete Account', style: TextStyle(color: colorScheme.error)),
              ),
            ],
          );
        },
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
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
          ),
        ],
      ),
    );
  }
}
