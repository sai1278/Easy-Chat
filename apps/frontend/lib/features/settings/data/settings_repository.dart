import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/user_settings.dart';

final userSettingsNotifierProvider = StateNotifierProvider<UserSettingsNotifier, UserSettings>((ref) {
  return UserSettingsNotifier();
});

class UserSettingsNotifier extends StateNotifier<UserSettings> {
  static const _keyDiscoverable = 'settings_discoverable';
  static const _keyNotifyNearby = 'settings_notify_nearby';
  static const _keyNotifyChat = 'settings_notify_chat';
  static const _keyEncryptSessions = 'settings_encrypt_sessions';

  UserSettingsNotifier() : super(const UserSettings()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = UserSettings(
        discoverable: prefs.getBool(_keyDiscoverable) ?? true,
        notifyNearbyPeers: prefs.getBool(_keyNotifyNearby) ?? true,
        notifyChatMessages: prefs.getBool(_keyNotifyChat) ?? true,
        encryptLocalSessions: prefs.getBool(_keyEncryptSessions) ?? true,
      );
    } catch (_) {}
  }

  Future<void> toggleDiscoverable(bool val) async {
    state = state.copyWith(discoverable: val);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDiscoverable, val);
  }

  Future<void> toggleNotifyNearby(bool val) async {
    state = state.copyWith(notifyNearbyPeers: val);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyNotifyNearby, val);
  }

  Future<void> toggleNotifyChat(bool val) async {
    state = state.copyWith(notifyChatMessages: val);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyNotifyChat, val);
  }

  Future<void> toggleEncryptSessions(bool val) async {
    state = state.copyWith(encryptLocalSessions: val);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEncryptSessions, val);
  }
}
