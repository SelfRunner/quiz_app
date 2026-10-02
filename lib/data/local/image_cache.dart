import 'dart:typed_data';

import 'package:hive_ce/hive_ce.dart';

import 'image_cache_factory_stub.dart'
    if (dart.library.io) 'image_cache_factory_io.dart'
    as platform;

/// Local bytes for note images, keyed by storage path
/// (`{ownerId}/{noteId}/{file}`). Holds both images saved on this device
/// (pending upload) and downloaded copies.
abstract interface class LocalImageCache {
  Future<Uint8List?> read(String path);
  Future<void> write(String path, Uint8List bytes);
  Future<void> remove(String path);

  /// Removes every image whose path starts with [prefix] (e.g. `owner/note/`).
  Future<void> removePrefix(String prefix);
  Future<void> clear();
}

/// Platform default: files under the app support directory on native,
/// the [HiveImageCache] box on web.
LocalImageCache createPlatformImageCache(Box<Uint8List> webBox) =>
    platform.createPlatformImageCache(webBox);

/// [LocalImageCache] in a Hive `Box<Uint8List>` (web, tests).
class HiveImageCache implements LocalImageCache {
  HiveImageCache(this.box);

  final Box<Uint8List> box;

  @override
  Future<Uint8List?> read(String path) async => box.get(path);

  @override
  Future<void> write(String path, Uint8List bytes) => box.put(path, bytes);

  @override
  Future<void> remove(String path) => box.delete(path);

  @override
  Future<void> removePrefix(String prefix) => box.deleteAll(
    box.keys.whereType<String>().where((k) => k.startsWith(prefix)).toList(),
  );

  @override
  Future<void> clear() => box.clear();
}
