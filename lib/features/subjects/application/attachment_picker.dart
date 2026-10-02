import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A file chosen for upload. [size] is known up front (when the platform
/// reports it) so oversized files are rejected before their bytes are read.
class PickedAttachmentFile {
  const PickedAttachmentFile({
    required this.name,
    required this.size,
    required this.read,
  });

  /// Wraps already-loaded [bytes].
  factory PickedAttachmentFile.bytes(String name, Uint8List bytes) =>
      PickedAttachmentFile(
        name: name,
        size: bytes.lengthInBytes,
        read: () async => bytes,
      );

  final String name;

  /// Size in bytes, or null when unknown until read.
  final int? size;
  final Future<Uint8List> Function() read;
}

/// Picks files for a subject's "Files" library. Override in tests.
abstract interface class AttachmentFilePicker {
  /// Lets the user pick one or more files; empty when cancelled.
  Future<List<PickedAttachmentFile>> pickFiles();
}

/// File extensions offered by the picker (PDF, images, text, Word, audio,
/// video).
const List<String> kAttachmentExtensions = [
  'pdf',
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'heic',
  'bmp',
  'txt',
  'md',
  'docx',
  'mp3',
  'wav',
  'm4a',
  'aac',
  'ogg',
  'flac',
  'mp4',
  'mov',
  'webm',
  'mkv',
  'avi',
];

/// `file_picker` based implementation (all platforms).
class DefaultAttachmentFilePicker implements AttachmentFilePicker {
  const DefaultAttachmentFilePicker();

  @override
  Future<List<PickedAttachmentFile>> pickFiles() async {
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Add files',
      type: FileType.custom,
      allowedExtensions: kAttachmentExtensions,
    );
    return [
      for (final f in files)
        PickedAttachmentFile(
          name: f.name,
          size: f.lengthSync(),
          read: f.readAsBytes,
        ),
    ];
  }
}

final attachmentFilePickerProvider = Provider<AttachmentFilePicker>(
  (ref) => const DefaultAttachmentFilePicker(),
);
