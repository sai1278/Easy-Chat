import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'entities/message_entity.dart';
import 'entities/user_entity.dart';

class IsarService {
  late final Isar _isar;

  IsarService._(this._isar);

  static Future<IsarService> init() async {
    final Isar isar;
    if (kIsWeb) {
      isar = await Isar.open(
        [
          MessageEntitySchema,
          UserEntitySchema,
        ],
        directory: '',
      );
    } else {
      // Locate the device documents directory for persistent storage
      final dir = await getApplicationDocumentsDirectory();
      isar = await Isar.open(
        [
          MessageEntitySchema,
          UserEntitySchema,
        ],
        directory: dir.path,
      );
    }
    return IsarService._(isar);
  }

  Isar get isar => _isar;
}
