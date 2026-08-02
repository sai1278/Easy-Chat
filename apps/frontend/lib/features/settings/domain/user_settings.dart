class UserSettings {
  final bool discoverable;
  final bool notifyNearbyPeers;
  final bool notifyChatMessages;
  final bool encryptLocalSessions;

  const UserSettings({
    this.discoverable = true,
    this.notifyNearbyPeers = true,
    this.notifyChatMessages = true,
    this.encryptLocalSessions = true,
  });

  UserSettings copyWith({
    bool? discoverable,
    bool? notifyNearbyPeers,
    bool? notifyChatMessages,
    bool? encryptLocalSessions,
  }) {
    return UserSettings(
      discoverable: discoverable ?? this.discoverable,
      notifyNearbyPeers: notifyNearbyPeers ?? this.notifyNearbyPeers,
      notifyChatMessages: notifyChatMessages ?? this.notifyChatMessages,
      encryptLocalSessions: encryptLocalSessions ?? this.encryptLocalSessions,
    );
  }
}
