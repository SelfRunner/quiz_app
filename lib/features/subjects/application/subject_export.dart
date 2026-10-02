import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/export_menu.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/models.dart';
import '../../../data/repositories/repository_support.dart'
    show noteImageRefsIn;
import '../../../io/note_export.dart';

/// Zips [subject]: one Markdown file per note (images that are available
/// locally or online go to `images/`), quizzes as JSON and decks as CSV
/// (see `subjectToZip`).
Future<ExportFile> buildSubjectZip(WidgetRef ref, Subject subject) async {
  final notes = await ref
      .read(noteRepositoryProvider)
      .watchBySubject(subject.id)
      .first;
  final quizzes = await ref
      .read(quizRepositoryProvider)
      .watchBySubject(subject.id)
      .first;
  final decks = await ref
      .read(deckRepositoryProvider)
      .watchBySubject(subject.id)
      .first;
  final images = <String, Uint8List>{};
  final store = ref.read(imageStoreProvider);
  for (final note in notes) {
    for (final image in noteImageRefsIn(note.contentMd)) {
      try {
        final bytes = await store.load(image);
        if (bytes != null) images[image.storagePath] = bytes;
      } catch (_) {
        // Missing image: its link stays as is.
      }
    }
  }
  final bytes = subjectToZip(
    subject,
    notes: notes,
    quizzes: quizzes,
    decks: decks,
    images: images,
  );
  return ('${safeFileName(subject.title, fallback: 'subject')}.zip', bytes);
}

/// "Markdown (.zip)" export of [subject] for an `ExportMenu` / `runExport`.
ExportItem subjectExportItem(WidgetRef ref, Subject subject) => ExportItem(
  key: const Key('export-subject-zip'),
  label: 'Markdown (.zip)',
  icon: Icons.folder_zip_outlined,
  build: () => buildSubjectZip(ref, subject),
);
