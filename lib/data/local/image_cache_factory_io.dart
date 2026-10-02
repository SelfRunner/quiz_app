import 'dart:io';
import 'dart:typed_data';

import 'package:hive_ce/hive_ce.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'image_cache.dart';

LocalImageCache createPlatformImageCache(Box<Uint8List> webBox) =>
    FileImageCache(() async {
      final base = await getApplicationSupportDirectory();
      return Directory(p.join(base.path, 'note_images'));
    });

LocalImageCache createPlatformAttachmentCache(LazyBox<Uint8List> webBox) =>
    FileImageCache(() async {
      final base = await getApplicationSupportDirectory();
      return Directory(p.join(base.path, 'attachments'));
    });

/// [LocalImageCache] storing one file per image under a root directory,
/// mirroring the storage path (`root/{owner}/{note}/{file}`).
class FileImageCache implements LocalImageCache {
  FileImageCache(this._resolveRoot);

  final Future<Directory> Function() _resolveRoot;
  Future<Directory>? _root;

  Future<Directory> get _dir => _root ??= _resolveRoot();

  Future<String> _pathFor(String storagePath) async {
    final parts = storagePath
        .split('/')
        .where((s) => s.isNotEmpty && s != '.' && s != '..');
    return p.joinAll([(await _dir).path, ...parts]);
  }

  @override
  Future<Uint8List?> read(String path) async {
    final file = File(await _pathFor(path));
    if (!file.existsSync()) return null;
    return file.readAsBytes();
  }

  @override
  Future<void> write(String path, Uint8List bytes) async {
    final file = File(await _pathFor(path));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> remove(String path) async {
    final file = File(await _pathFor(path));
    if (file.existsSync()) await file.delete();
  }

  @override
  Future<void> removePrefix(String prefix) async {
    final dir = Directory(await _pathFor(prefix));
    if (dir.existsSync()) await dir.delete(recursive: true);
  }

  @override
  Future<void> clear() async {
    final dir = await _dir;
    if (dir.existsSync()) await dir.delete(recursive: true);
  }
}
