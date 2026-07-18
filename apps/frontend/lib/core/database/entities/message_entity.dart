import 'package:isar/isar.dart';

part 'message_entity.g.dart';

@Collection()
class MessageEntity {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String messageId;

  @Index()
  late String roomId;

  late String senderId;
  late List<int> encryptedPayload;
  late String idempotencyKey;

  @Index()
  late DateTime createdAt;
}
