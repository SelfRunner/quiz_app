import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../errors/app_exception.dart';

/// Android / iOS: the system save sheet (`file_picker`; null when the user
/// cancels or the platform handled it). Desktop (or when the sheet is
/// unavailable): writes [bytes] to the Downloads folder, else the temporary
/// folder, never overwriting an existing file, and returns the path.
Future<String?> saveFileBytes(
  String fileName,
  Uint8List bytes,
  String? mimeType,
) async {
  if (Platform.isAndroid || Platform.isIOS) {
    try {
      final uri = await FilePicker.saveFile(
        fileName: fileName,
        bytes: bytes,
        mimeType: mimeType ?? 'application/octet-stream',
      );
      return uri != null && uri.scheme == 'file' ? uri.toFilePath() : null;
    } on Exception {
      // Fall back to the app's folders below.
    }
  }
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
