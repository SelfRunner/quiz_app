import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/errors/app_exception.dart';

/// Writes [bytes] to the Downloads folder (desktop) or the temporary folder,
/// never overwriting an existing file. Returns the path.
Future<String?> saveFileBytes(
  String fileName,
  Uint8List bytes,
  String? mimeType,
) async {
  try {
    Directory? dir;
    try {
      dir = await getDownloadsDirectory();
    } catch (_) {
      dir = null;
    }
    dir ??= await getTemporaryDirectory();
    await dir.create(recursive: true);
    final safe = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    final base = safe.isEmpty ? 'file' : safe;
    final stem = p.basenameWithoutExtension(base);
    final ext = p.extension(base);
    var file = File(p.join(dir.path, base));
    for (var i = 1; file.existsSync(); i++) {
      file = File(p.join(dir.path, '$stem ($i)$ext'));
    }
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  } on FileSystemException catch (e) {
    throw StorageException('Could not save "$fileName".', cause: e);
  }
}
