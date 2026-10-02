import 'dart:typed_data';

import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../data/models/attachment.dart';
import '../domain/generation_sources.dart';

/// A file chosen with [AiFilePicker].
class PickedFile {
  const PickedFile({required this.name, required this.bytes, this.mimeType});

  final String name;
  final String? mimeType;
  final Uint8List bytes;
}

/// Opens the platform file chooser. Abstracted so widget tests can inject
/// files.
abstract interface class AiFilePicker {
  /// Lets the user pick one or more files with one of [extensions] (no
  /// dots). Empty when cancelled. Throws [ValidationException] when a file
  /// is larger than [Attachment.maxSizeBytes].
  Future<List<PickedFile>> pick({required List<String> extensions});
}

class PlatformAiFilePicker implements AiFilePicker {
  const PlatformAiFilePicker();

  @override
  Future<List<PickedFile>> pick({required List<String> extensions}) async {
    final files = await fp.FilePicker.pickFiles(
      type: fp.FileType.custom,
      allowedExtensions: extensions,
    );
    final picked = <PickedFile>[];
    for (final f in files) {
      final size = f.lengthSync() ?? await f.length();
      if (size != null && size > Attachment.maxSizeBytes) {
        throw ValidationException(
          '"${f.name}" is ${formatFileSize(size)}; files can be up to '
          '${formatFileSize(Attachment.maxSizeBytes)}.',
        );
      }
      picked.add(PickedFile(name: f.name, bytes: await f.readAsBytes()));
    }
    return picked;
  }
}

final aiFilePickerProvider = Provider<AiFilePicker>(
  (ref) => const PlatformAiFilePicker(),
);
