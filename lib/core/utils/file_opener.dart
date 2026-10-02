import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A file the user picked for import.
class OpenedFile {
  const OpenedFile(this.name, this.bytes);

  final String name;
  final Uint8List bytes;

  /// The bytes as UTF-8 text (malformed sequences replaced, BOM dropped).
  String get text {
    final s = utf8.decode(bytes, allowMalformed: true);
    return s.startsWith('﻿') ? s.substring(1) : s;
  }
}

/// Lets the user pick one file to import (CSV, TSV, JSON, Markdown, ...).
/// Override [fileOpenerProvider] in tests.
abstract interface class FileOpener {
  /// The picked file, or null when cancelled. [extensions] without dots.
  Future<OpenedFile?> pick({
    List<String> extensions = const [],
    String? dialogTitle,
  });
}

class DefaultFileOpener implements FileOpener {
  const DefaultFileOpener();

  @override
  Future<OpenedFile?> pick({
    List<String> extensions = const [],
    String? dialogTitle,
  }) async {
    final file = await FilePicker.pickFile(
      dialogTitle: dialogTitle,
      type: extensions.isEmpty ? FileType.any : FileType.custom,
      allowedExtensions: extensions.isEmpty ? null : extensions,
    );
    if (file == null) return null;
    return OpenedFile(file.name, await file.readAsBytes());
  }
}

final fileOpenerProvider = Provider<FileOpener>(
  (ref) => const DefaultFileOpener(),
);
