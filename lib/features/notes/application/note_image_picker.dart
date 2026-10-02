import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

/// An image chosen by the user for a note.
class PickedImage {
  const PickedImage({required this.bytes, required this.extension, this.name});

  final Uint8List bytes;

  /// Lowercase, without dot (e.g. `png`).
  final String extension;
  final String? name;
}

/// Picks images for notes. Override in tests.
abstract interface class NoteImagePicker {
  /// Returns null when the user cancels.
  Future<PickedImage?> pickImage();
}

/// `image_picker` gallery/file picker (Android, web, desktop). Large photos
/// are downscaled where the platform supports it.
class DefaultNoteImagePicker implements NoteImagePicker {
  DefaultNoteImagePicker([ImagePicker? picker])
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  static const Set<String> supportedExtensions = {
    'png',
    'jpg',
    'jpeg',
    'gif',
    'webp',
    'bmp',
  };

  @override
  Future<PickedImage?> pickImage() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 85,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    return PickedImage(
      bytes: bytes,
      extension: imageExtension(file.name, file.mimeType),
      name: file.name,
    );
  }
}

/// Extension from a file name or MIME type, defaulting to `png`.
String imageExtension(String name, [String? mimeType]) {
  final dot = name.lastIndexOf('.');
  if (dot != -1 && dot < name.length - 1) {
    final ext = name.substring(dot + 1).toLowerCase();
    if (DefaultNoteImagePicker.supportedExtensions.contains(ext)) {
      return ext == 'jpeg' ? 'jpg' : ext;
    }
  }
  final mime = mimeType?.toLowerCase() ?? '';
  if (mime.contains('jpeg') || mime.contains('jpg')) return 'jpg';
  if (mime.contains('gif')) return 'gif';
  if (mime.contains('webp')) return 'webp';
  return 'png';
}

final noteImagePickerProvider = Provider<NoteImagePicker>(
  (ref) => DefaultNoteImagePicker(),
);
