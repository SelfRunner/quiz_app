import '../../../ai/text_extractor.dart' show TextExtractor;
import '../../../core/errors/app_exception.dart';
import '../../../data/models/models.dart';
import '../../../data/repositories/attachment_repository.dart';
import 'attachment_picker.dart';

/// Result of adding picked files to a subject.
class AttachmentUploadOutcome {
  const AttachmentUploadOutcome({required this.added, required this.errors});

  final List<Attachment> added;

  /// One user-facing line per file that was not added.
  final List<String> errors;
}

/// Human-readable file size ("820 KB", "1.4 MB").
String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value >= 10 || unit == 0 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

/// Adds [files] to [subjectId] through [repo]: rejects oversized files
/// before reading them, extracts text from .txt/.md/.docx (stored as
/// `extractedText`), and keeps going when one file fails.
Future<AttachmentUploadOutcome> addAttachments(
  AttachmentRepository repo,
  String subjectId,
  List<PickedAttachmentFile> files,
) async {
  final added = <Attachment>[];
  final errors = <String>[];
  const limit = Attachment.maxSizeBytes;
  for (final file in files) {
    final size = file.size;
    if (size != null && size > limit) {
      errors.add(
        '"${file.name}" is ${formatFileSize(size)}; files can be at most '
        '${formatFileSize(limit)}.',
      );
      continue;
    }
    try {
      final bytes = await file.read();
      if (bytes.lengthInBytes > limit) {
        errors.add(
          '"${file.name}" is ${formatFileSize(bytes.lengthInBytes)}; files '
          'can be at most ${formatFileSize(limit)}.',
        );
        continue;
      }
      if (bytes.isEmpty) {
        errors.add('"${file.name}" is empty.');
        continue;
      }
      final mimeType = mimeTypeForFileName(file.name);
      String? text;
      if (TextExtractor.canExtract(file.name, mimeType)) {
        text = TextExtractor.extract(file.name, mimeType, bytes);
      }
      final attachment = await repo.add(
        subjectId: subjectId,
        name: file.name,
        mimeType: mimeType,
        bytes: bytes,
        extractedText: text,
      );
      added.add(attachment);
    } on AppException catch (e) {
      errors.add('"${file.name}": ${e.message}');
    } catch (_) {
      errors.add('"${file.name}" could not be read.');
    }
  }
  return AttachmentUploadOutcome(added: added, errors: errors);
}
