import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'file_saver_io.dart'
    if (dart.library.js_interop) 'file_saver_web.dart'
    as impl;

/// Hands a file's bytes to the user: a browser download (anchor) on the
/// web, the system "Save as" sheet on Android / iOS, and a file in the
/// Downloads (else temporary) folder on desktop. Override
/// [fileSaverProvider] in tests.
abstract interface class FileSaver {
  /// Returns the saved file's path, or null when the platform handled it
  /// (e.g. a browser download, a mobile save sheet).
  Future<String?> save(String fileName, Uint8List bytes, {String? mimeType});
}

class DefaultFileSaver implements FileSaver {
  const DefaultFileSaver();

  @override
  Future<String?> save(String fileName, Uint8List bytes, {String? mimeType}) =>
      impl.saveFileBytes(fileName, bytes, mimeType ?? mimeTypeFor(fileName));
}

final fileSaverProvider = Provider<FileSaver>(
  (ref) => const DefaultFileSaver(),
);

/// MIME type for common export file names (by extension).
String mimeTypeFor(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  return switch (ext) {
    'zip' => 'application/zip',
    'json' => 'application/json',
    'csv' => 'text/csv',
    'tsv' => 'text/tab-separated-values',
    'txt' => 'text/plain',
    'md' => 'text/markdown',
    'pdf' => 'application/pdf',
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    _ => 'application/octet-stream',
  };
}
