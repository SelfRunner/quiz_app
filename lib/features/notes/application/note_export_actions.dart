import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/widgets/error_message.dart';
import '../../../core/widgets/export_menu.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/models.dart';
import '../../../data/repositories/organization_repository.dart';
import '../../../io/note_export.dart';
import 'note_pdf.dart';

/// Base file name (no extension) for exports of [note].
String noteExportBaseName(Note note) =>
    safeFileName(note.title, fallback: 'note');

/// Markdown file of [note] (YAML front matter: title, subject, tags, dates).
String noteMarkdownExport(Note note, {String? subjectTitle}) =>
    noteToMarkdown(note, subjectTitle: subjectTitle);

/// Images for the PDF export: `note-image://` refs via the image store
/// (cache first), web URLs downloaded best effort (may fail on web because
/// of CORS: the PDF then shows the alt text).
PdfImageLoader noteImageLoader(WidgetRef ref) {
  final store = ref.read(imageStoreProvider);
  return (url) async {
    final imageRef = NoteImageRef.tryParse(url);
    if (url.startsWith('${NoteImageRef.scheme}://') && imageRef != null) {
      return store.load(imageRef);
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return null;
    }
    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    return response.statusCode == 200 ? response.bodyBytes : null;
  };
}

/// Markdown (.md) and PDF exports of [note] for an `ExportMenu` /
/// `runExport`.
List<ExportItem> noteExportItems(
  WidgetRef ref,
  Note note, {
  String? subjectTitle,
}) {
  final base = noteExportBaseName(note);
  return [
    ExportItem(
      key: const Key('export-note-md'),
      label: 'Markdown (.md)',
      icon: Icons.description_outlined,
      build: () async => (
        '$base.md',
        Uint8List.fromList(
          utf8.encode(noteMarkdownExport(note, subjectTitle: subjectTitle)),
        ),
      ),
    ),
    ExportItem(
      key: const Key('export-note-pdf'),
      label: 'PDF (.pdf)',
      icon: Icons.picture_as_pdf_outlined,
      build: () async => (
        '$base.pdf',
        await noteToPdf(
          note,
          subjectTitle: subjectTitle,
          loadImage: noteImageLoader(ref),
        ),
      ),
    ),
  ];
}

/// Copies [note] as Markdown (with front matter) to the clipboard.
Future<void> copyNoteAsMarkdown(
  BuildContext context,
  Note note, {
  String? subjectTitle,
}) async {
  try {
    await Clipboard.setData(
      ClipboardData(text: noteMarkdownExport(note, subjectTitle: subjectTitle)),
    );
    if (context.mounted) showAppSnackBar(context, 'Copied as Markdown');
  } catch (e) {
    if (context.mounted) showErrorSnackBar(context, e, prefix: 'Copy failed');
  }
}

/// Pins / unpins [note] (owner only) from a menu; errors as a snackbar.
Future<void> setNotePinned(
  BuildContext context,
  WidgetRef ref,
  Note note,
  bool pinned,
) async {
  try {
    await ref
        .read(organizationRepositoryProvider)
        .setPinned(TaggableKind.note, note.id, pinned);
    if (context.mounted) {
      showAppSnackBar(context, pinned ? 'Note pinned' : 'Note unpinned');
    }
  } catch (e) {
    if (context.mounted) showErrorSnackBar(context, e);
  }
}

/// [notes] with pinned ones first (each group keeps its order).
List<Note> notesPinnedFirst(List<Note> notes) => [
  for (final n in notes)
    if (n.pinned) n,
  for (final n in notes)
    if (!n.pinned) n,
];
