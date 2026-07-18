class ChatSessionArgs {
  final String roomId;
  final String peerId;

  const ChatSessionArgs({
    required this.roomId,
    required this.peerId,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChatSessionArgs &&
        other.roomId == roomId &&
        other.peerId == peerId;
  }

  @override
  int get hashCode => roomId.hashCode ^ peerId.hashCode;
}
