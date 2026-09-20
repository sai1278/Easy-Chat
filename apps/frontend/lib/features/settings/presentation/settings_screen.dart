import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
          backgroundColor: ClayColors.cardSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(
            title,
            style: TextStyle(fontWeight: FontWeight.w800, color: ClayColors.textPrimary),
          ),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: 'Enter new $title',
              filled: true,
              fillColor: ClayColors.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: ClayColors.borderSubtle),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: ClayColors.textSecondary)),
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
        backgroundColor: ClayColors.cardSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Log Out', style: TextStyle(fontWeight: FontWeight.w800, color: ClayColors.textPrimary)),
        content: Text('Are you sure you want to log out of Easy Chat?', style: TextStyle(color: ClayColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: ClayColors.textSecondary)),
          ),
          ClayButton(
            label: 'Log Out',
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
        backgroundColor: ClayColors.cardSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Delete Account', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFDC2626))),
        content: Text(
          'This action is permanent and will delete your profile data from Easy Chat.',
          style: TextStyle(color: ClayColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: ClayColors.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
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
          'Settings',
          style: TextStyle(
            color: ClayColors.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 20,
            letterSpacing: -0.5,
          ),
        ),
      ),
      body: profileAsync.when(
        loading: () => Center(child: CircularProgressIndicator(color: ClayColors.accent)),
        error: (err, _) => Center(child: Text('Error loading settings: $err')),
        data: (profile) {
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            children: [
              // User Profile Clay Card
              ClayCard(
                padding: const EdgeInsets.all(18.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: ClayShadows.card,
                            border: Border.all(color: ClayColors.borderSubtle),
                          ),
                          child: ClipOval(
                            child: profile.avatarUrl.isNotEmpty
                                ? Image.network(profile.avatarUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _buildAvatarInitial(profile))
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
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 17,
                                  color: ClayColors.textPrimary,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              Text(
                                '@${profile.username}',
                                style: TextStyle(fontSize: 13, color: ClayColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        ClaySecondaryButton(
                          label: 'Edit',
                          icon: Icons.edit_rounded,
                          onPressed: () => context.push('/profile'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Divider(color: ClayColors.borderSubtle),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.badge_outlined, color: ClayColors.accent, size: 20),
                      title: Text('Display Name', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ClayColors.textPrimary)),
                      subtitle: Text(
                        profile.displayName.isNotEmpty ? profile.displayName : 'Not set',
                        style: TextStyle(fontSize: 13, color: ClayColors.textSecondary),
                      ),
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
                      leading: Icon(Icons.info_outline_rounded, color: ClayColors.accent, size: 20),
                      title: Text('Bio', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ClayColors.textPrimary)),
                      subtitle: Text(
                        profile.bio.isNotEmpty ? profile.bio : 'No bio added',
                        style: TextStyle(fontSize: 13, color: ClayColors.textSecondary),
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

              // Spatial Privacy & Discovery Section
              const _SectionHeader(title: 'Privacy & Visibility', icon: Icons.visibility_outlined),
              ClayCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    SwitchListTile(
                      value: settings.discoverable,
                      activeColor: ClayColors.accent,
                      onChanged: (val) => settingsNotifier.toggleDiscoverable(val),
                      title: Text('Discoverable Nearby', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ClayColors.textPrimary)),
                      subtitle: Text('Allow nearby people to discover your profile within 1 km.', style: TextStyle(fontSize: 12, color: ClayColors.textSecondary)),
                      secondary: Icon(Icons.radar_rounded, color: ClayColors.accent),
                    ),
                    Divider(height: 1, color: ClayColors.borderSubtle),
                    SwitchListTile(
                      value: settings.encryptLocalSessions,
                      activeColor: ClayColors.accent,
                      onChanged: (val) => settingsNotifier.toggleEncryptSessions(val),
                      title: Text('Secure Local Storage', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ClayColors.textPrimary)),
                      subtitle: Text('Keep your conversations encrypted on device.', style: TextStyle(fontSize: 12, color: ClayColors.textSecondary)),
                      secondary: Icon(Icons.lock_outline_rounded, color: ClayColors.accent),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Notifications Section
              const _SectionHeader(title: 'Notifications', icon: Icons.notifications_outlined),
              ClayCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    SwitchListTile(
                      value: settings.notifyNearbyPeers,
                      activeColor: ClayColors.accent,
                      onChanged: (val) => settingsNotifier.toggleNotifyNearby(val),
                      title: Text('Nearby Alerts', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ClayColors.textPrimary)),
                      subtitle: Text('Get notified when someone enters your nearby area.', style: TextStyle(fontSize: 12, color: ClayColors.textSecondary)),
                      secondary: Icon(Icons.sensors_rounded, color: ClayColors.accent),
                    ),
                    Divider(height: 1, color: ClayColors.borderSubtle),
                    SwitchListTile(
                      value: settings.notifyChatMessages,
                      activeColor: ClayColors.accent,
                      onChanged: (val) => settingsNotifier.toggleNotifyChat(val),
                      title: Text('Chat Notifications', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ClayColors.textPrimary)),
                      subtitle: Text('Receive alerts for incoming messages.', style: TextStyle(fontSize: 12, color: ClayColors.textSecondary)),
                      secondary: Icon(Icons.chat_bubble_outline_rounded, color: ClayColors.accent),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // About Section with Official Easy Chat Brand
              const _SectionHeader(title: 'About Easy Chat', icon: Icons.info_outline_rounded),
              ClayCard(
                padding: const EdgeInsets.all(18.0),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: ClayShadows.card,
                      ),
                      padding: const EdgeInsets.all(6),
                      child: const EasyChatLogoMark(size: 30),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Easy Chat',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: ClayColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Private, ephemeral nearby messaging',
                            style: TextStyle(fontSize: 12, color: ClayColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    ClayBadge(label: 'v1.0.0'),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Account Actions Section
              ClaySecondaryButton(
                label: 'Log Out',
                icon: Icons.logout_rounded,
                onPressed: _handleLogout,
              ),
              const SizedBox(height: 10),
              Center(
                child: TextButton.icon(
                  onPressed: _handleDeleteAccount,
                  icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFDC2626)),
                  label: const Text('Delete Account', style: TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.w600)),
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
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: ClayColors.accent,
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
          Icon(icon, size: 16, color: ClayColors.accent),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: ClayColors.textPrimary,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}
