// Chat request domain model representing explicit request lifecycle
// States: PENDING, ACCEPTED, DENIED, CANCELLED, NONE

enum ChatRequestStatus {
  none,
  pending,
  accepted,
  denied,
  cancelled;

  static ChatRequestStatus fromString(String? val) {
    switch (val?.toUpperCase()) {
      case 'PENDING':
        return ChatRequestStatus.pending;
      case 'ACCEPTED':
        return ChatRequestStatus.accepted;
      case 'DENIED':
        return ChatRequestStatus.denied;
      case 'CANCELLED':
        return ChatRequestStatus.cancelled;
      default:
        return ChatRequestStatus.none;
    }
  }

  String get value {
    switch (this) {
      case ChatRequestStatus.pending:
        return 'PENDING';
      case ChatRequestStatus.accepted:
        return 'ACCEPTED';
      case ChatRequestStatus.denied:
        return 'DENIED';
      case ChatRequestStatus.cancelled:
        return 'CANCELLED';
      case ChatRequestStatus.none:
        return 'NONE';
    }
  }
}

class ChatRequest {
  final String id;
  final String senderId;
  final String recipientId;
  final String? roomId;
  final ChatRequestStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? respondedAt;
  final String? senderDisplayName;
  final String? senderUsername;
  final String? senderAvatarUrl;
  final String? senderBio;

  const ChatRequest({
    required this.id,
    required this.senderId,
    required this.recipientId,
    this.roomId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.respondedAt,
    this.senderDisplayName,
    this.senderUsername,
    this.senderAvatarUrl,
    this.senderBio,
  });

  factory ChatRequest.fromJson(Map<String, dynamic> json) {
    return ChatRequest(
      id: json['id'] as String? ?? '',
      senderId: (json['sender_id'] ?? json['senderId']) as String? ?? '',
      recipientId: (json['recipient_id'] ?? json['recipientId']) as String? ?? '',
      roomId: (json['room_id'] ?? json['roomId']) as String?,
      status: ChatRequestStatus.fromString(json['status'] as String?),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? json['createdAt'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? json['updatedAt'] as String? ?? '') ?? DateTime.now(),
      respondedAt: json['responded_at'] != null ? DateTime.tryParse(json['responded_at'] as String) : null,
      senderDisplayName: (json['sender_display_name'] ?? json['senderDisplayName']) as String?,
      senderUsername: (json['sender_username'] ?? json['senderUsername']) as String?,
      senderAvatarUrl: (json['sender_avatar_url'] ?? json['senderAvatarUrl']) as String?,
      senderBio: (json['sender_bio'] ?? json['senderBio']) as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender_id': senderId,
      'recipient_id': recipientId,
      'room_id': roomId,
      'status': status.value,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'responded_at': respondedAt?.toIso8601String(),
      'sender_display_name': senderDisplayName,
      'sender_username': senderUsername,
      'sender_avatar_url': senderAvatarUrl,
      'sender_bio': senderBio,
    };
  }

  ChatRequest copyWith({
    String? id,
    String? senderId,
    String? recipientId,
    String? roomId,
    ChatRequestStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? respondedAt,
    String? senderDisplayName,
    String? senderUsername,
    String? senderAvatarUrl,
    String? senderBio,
  }) {
    return ChatRequest(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      recipientId: recipientId ?? this.recipientId,
      roomId: roomId ?? this.roomId,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      respondedAt: respondedAt ?? this.respondedAt,
      senderDisplayName: senderDisplayName ?? this.senderDisplayName,
      senderUsername: senderUsername ?? this.senderUsername,
      senderAvatarUrl: senderAvatarUrl ?? this.senderAvatarUrl,
      senderBio: senderBio ?? this.senderBio,
    );
  }
}
