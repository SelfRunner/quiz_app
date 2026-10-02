import 'dart:typed_data';

import 'package:hive_ce/hive_ce.dart';

import 'image_cache_factory_stub.dart'
    if (dart.library.io) 'image_cache_factory_io.dart'
    as platform;

/// Local blob bytes keyed by storage path. Used for note images
/// (`{ownerId}/{noteId}/{file}`) and, as a separate instance, for subject
/// attachments (`{ownerId}/{subjectId}/{id}/{file}`). Holds both blobs saved
/// on this device (pending upload) and downloaded copies.
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

/// Platform default for attachment blobs: files under
/// `{app support}/attachments` on native, the lazy [LazyHiveBlobCache] box on
/// web (attachments can be large, so values are not kept in memory).
LocalImageCache createPlatformAttachmentCache(LazyBox<Uint8List> webBox) =>
    platform.createPlatformAttachmentCache(webBox);

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

/// [LocalImageCache] in a lazy Hive box: only keys are kept in memory,
/// values are read on demand (web attachment cache, tests).
class LazyHiveBlobCache implements LocalImageCache {
  LazyHiveBlobCache(this.box);

  final LazyBox<Uint8List> box;

  @override
  Future<Uint8List?> read(String path) => box.get(path);

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
