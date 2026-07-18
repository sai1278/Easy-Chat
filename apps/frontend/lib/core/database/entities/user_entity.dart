import 'package:isar/isar.dart';

part 'user_entity.g.dart';

@Collection()
class UserEntity {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String userId;

  late String username;
  late String avatarUrl;
  late bool isOnline;
  late DateTime lastSeenAt;
  late double distanceMeters;
}
