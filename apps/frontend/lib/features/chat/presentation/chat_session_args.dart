import '../domain/chat_request.dart';

class ChatSessionArgs {
  final String roomId;
  final String peerId;
  final String? peerName;
  final ChatRequestStatus requestStatus;

  const ChatSessionArgs({
    required this.roomId,
    required this.peerId,
    this.peerName,
    this.requestStatus = ChatRequestStatus.accepted,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChatSessionArgs &&
        other.roomId == roomId &&
        other.peerId == peerId &&
        other.requestStatus == requestStatus;
  }

  @override
  int get hashCode => roomId.hashCode ^ peerId.hashCode ^ requestStatus.hashCode;
}
