import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'file_saver_io.dart'
    if (dart.library.js_interop) 'file_saver_web.dart'
    as impl;

/// Hands a file's bytes to the user: a browser download on the web, a file
/// in the Downloads (else temporary) folder elsewhere. Override in tests.
abstract interface class FileSaver {
  /// Returns the saved file's path, or null when the platform handled it
  /// (e.g. a browser download).
  Future<String?> save(String fileName, Uint8List bytes, {String? mimeType});
}

class DefaultFileSaver implements FileSaver {
  const DefaultFileSaver();

  @override
  Future<String?> save(String fileName, Uint8List bytes, {String? mimeType}) =>
      impl.saveFileBytes(fileName, bytes, mimeType);
}

final fileSaverProvider = Provider<FileSaver>(
  (ref) => const DefaultFileSaver(),
);
