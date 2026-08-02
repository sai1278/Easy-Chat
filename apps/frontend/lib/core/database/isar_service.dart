import 'dart:async';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'entities/message_entity.dart';
import 'entities/user_entity.dart';

/// Storage abstraction allowing platform-specific persistent storage adapters.
/// Native platforms (Android, iOS, Windows, macOS, Linux) use Isar 3.1.0.
/// Web platform uses WebStorageService in-memory/reactive storage to avoid Isar 3.x web runtime exception.
abstract class IsarService {
  Isar? get isar;
  Stream<List<MessageEntity>> watchMessages(String roomId);
  Future<void> saveMessage(MessageEntity message);
  Future<void> saveUser(UserEntity user);

  static Future<IsarService> init() async {
    if (kIsWeb) {
      return WebStorageService.init();
    } else {
      return NativeIsarService.init();
    }
  }
}

/// Native Isar implementation for Mobile and Desktop OS targets.
class NativeIsarService implements IsarService {
  final Isar _isar;

  NativeIsarService._(this._isar);

  static Future<NativeIsarService> init() async {
    final dir = await getApplicationDocumentsDirectory();

    Future<Isar> openIsar([String name = 'default']) async {
      return await Isar.open(
        [
          MessageEntitySchema,
          UserEntitySchema,
        ],
        directory: dir.path,
        name: name,
      );
    }

    try {
      final existing = Isar.getInstance();
      if (existing != null && existing.isOpen) {
        return NativeIsarService._(existing);
      }
      return NativeIsarService._(await openIsar());
    } catch (e) {
      final err = e.toString();
      if (err.contains("Collection id is invalid") || err.contains("schema") || err.contains("IllegalArg")) {
        developer.log("Isar schema mismatch detected, purging local database: $err");
        
        await _purgeIsarDatabase(dir.path, 'default');

        try {
          return NativeIsarService._(await openIsar('default'));
        } catch (retryErr) {
          developer.log("Retry with 'default' failed: $retryErr. Opening fresh instance 'default_v2'");
          await _purgeIsarDatabase(dir.path, 'default_v2');
          return NativeIsarService._(await openIsar('default_v2'));
        }
      }
      rethrow;
    }
  }

  static Future<void> _purgeIsarDatabase(String dirPath, String name) async {
    try {
      final existing = Isar.getInstance(name);
      if (existing != null && existing.isOpen) {
        await existing.close(deleteFromDisk: true);
      }
    } catch (_) {}

    final targets = [
      '$dirPath/$name.isar',
      '$dirPath/$name.isar.lock',
      '$dirPath/default.isar',
      '$dirPath/default.isar.lock',
    ];

    for (final targetPath in targets) {
      try {
        final type = FileSystemEntity.typeSync(targetPath);
        if (type == FileSystemEntityType.directory) {
          Directory(targetPath).deleteSync(recursive: true);
          developer.log("Purged Isar directory: $targetPath");
        } else if (type == FileSystemEntityType.file) {
          File(targetPath).deleteSync();
          developer.log("Purged Isar file: $targetPath");
        }
      } catch (err) {
        developer.log("Failed to purge $targetPath: $err");
      }
    }
  }

  @override
  Isar get isar => _isar;

  @override
  Stream<List<MessageEntity>> watchMessages(String roomId) {
    return _isar.messageEntitys
        .filter()
        .roomIdEqualTo(roomId)
        .sortByCreatedAt()
        .watch(fireImmediately: true);
  }

  @override
  Future<void> saveMessage(MessageEntity message) async {
    await _isar.writeTxn(() async {
      await _isar.messageEntitys.put(message);
    });
  }

  @override
  Future<void> saveUser(UserEntity user) async {
    await _isar.writeTxn(() async {
      await _isar.userEntitys.put(user);
    });
  }
}

/// Web-compatible Storage implementation avoiding Isar 3.x web runtime exception.
class WebStorageService implements IsarService {
  final Map<String, MessageEntity> _messages = {};
  final Map<String, UserEntity> _users = {};
  final _messageStreamController = StreamController<List<MessageEntity>>.broadcast();

  WebStorageService._();

  static Future<WebStorageService> init() async {
    return WebStorageService._();
  }

  @override
  Isar? get isar => null;

  @override
  Stream<List<MessageEntity>> watchMessages(String roomId) {
    final initialList = _getRoomMessages(roomId);
    final controller = StreamController<List<MessageEntity>>();
    controller.add(initialList);

    final sub = _messageStreamController.stream.listen((_) {
      if (!controller.isClosed) {
        controller.add(_getRoomMessages(roomId));
      }
    });

    controller.onCancel = () {
      sub.cancel();
      controller.close();
    };

    return controller.stream;
  }

  List<MessageEntity> _getRoomMessages(String roomId) {
    final list = _messages.values.where((m) => m.roomId == roomId).toList();
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  @override
  Future<void> saveMessage(MessageEntity message) async {
    _messages[message.messageId] = message;
    _messageStreamController.add(_getRoomMessages(message.roomId));
  }

  @override
  Future<void> saveUser(UserEntity user) async {
    _users[user.userId] = user;
  }
}
