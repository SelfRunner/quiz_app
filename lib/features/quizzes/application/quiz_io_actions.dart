import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/file_opener.dart';
import '../../../core/widgets/error_message.dart';
import '../../../core/widgets/export_menu.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/question.dart';
import '../../../data/models/quiz.dart';
import '../../../data/repositories/organization_repository.dart';
import '../../../io/import_report.dart';
import '../../../io/note_export.dart' show safeFileName;
import '../../../io/quiz_io.dart';
import '../widgets/quiz_format.dart' show plural;
import '../widgets/quiz_import_dialog.dart';

/// File extensions offered when importing a quiz.
const List<String> kQuizImportExtensions = ['json', 'csv'];

/// JSON (lossless) and CSV exports of [quiz].
List<ExportItem> quizExportItems(Quiz quiz) {
  final base = safeFileName(quiz.title, fallback: 'quiz');
  return [
    ExportItem(
      key: const Key('export-quiz-json'),
      label: 'JSON (.json)',
      icon: Icons.data_object,
      build: () async =>
          ('$base.json', Uint8List.fromList(utf8.encode(quizToJson(quiz)))),
    ),
    ExportItem(
      key: const Key('export-quiz-csv'),
      label: 'CSV (.csv)',
      icon: Icons.table_chart_outlined,
      build: () async =>
          ('$base.csv', Uint8List.fromList(utf8.encode(quizToCsv(quiz)))),
    ),
  ];
}

/// Parses an opened quiz file: `.csv` (or text that is not JSON) as CSV,
/// everything else as JSON.
ImportResult<Question> parseQuizFile(
  String fileName,
  String text, {
  required String Function() newId,
}) {
  final lower = fileName.toLowerCase();
  final trimmed = text.trimLeft();
  final json =
      lower.endsWith('.json') ||
      (!lower.endsWith('.csv') &&
          (trimmed.startsWith('{') || trimmed.startsWith('[')));
  return json
      ? importQuizJson(text, newId: newId)
      : importQuizCsv(text, newId: newId);
}

/// Title suggested for an import: the file's title, else the file name
/// without its extension, else "Imported quiz".
String suggestedQuizTitle(String fileName, ImportResult<Question> result) {
  final fromFile = result.title?.trim() ?? '';
  if (fromFile.isNotEmpty) return fromFile;
  final dot = fileName.lastIndexOf('.');
  final stem = (dot > 0 ? fileName.substring(0, dot) : fileName).trim();
  return stem.isEmpty ? 'Imported quiz' : stem;
}

/// Picks a JSON / CSV file, parses it and shows the preview (questions,
/// skipped rows by line, title field). On confirm creates the quiz in
/// [subjectId] (and [noteId]), applies the file's tags and opens it.
/// Returns the new quiz, or null when cancelled / failed.
Future<Quiz?> importNewQuiz(
  BuildContext context,
  WidgetRef ref, {
  required String subjectId,
  String? noteId,
}) async {
  final OpenedFile? file;
  try {
    file = await ref
        .read(fileOpenerProvider)
        .pick(extensions: kQuizImportExtensions, dialogTitle: 'Import quiz');
  } catch (e) {
    if (context.mounted) showErrorSnackBar(context, e, prefix: 'Import failed');
    return null;
  }
  if (file == null || !context.mounted) return null;
  final result = parseQuizFile(
    file.name,
    file.text,
    newId: ref.read(idGeneratorProvider),
  );
  final title = await showQuizImportPreview(
    context,
    fileName: file.name,
    result: result,
    initialTitle: suggestedQuizTitle(file.name, result),
  );
  if (title == null || !context.mounted) return null;
  try {
    final description = result.description?.trim();
    final quiz = await ref
        .read(quizRepositoryProvider)
        .create(
          subjectId: subjectId,
          noteId: noteId,
          title: title,
          description: description == null || description.isEmpty
              ? null
              : description,
          questions: result.items,
        );
    if (result.tags.isNotEmpty) {
      try {
        await ref
            .read(organizationRepositoryProvider)
            .setTags(TaggableKind.quiz, quiz.id, result.tags);
      } catch (_) {
        // Tags are best effort; the quiz itself was imported.
      }
    }
    if (!context.mounted) return quiz;
    showAppSnackBar(
      context,
      'Imported ${plural(result.items.length, 'question')}',
    );
    GoRouter.maybeOf(context)?.push<void>(AppRoutes.quiz(quiz.id)).ignore();
    return quiz;
  } catch (e) {
    if (context.mounted) showErrorSnackBar(context, e, prefix: 'Import failed');
    return null;
  }
}
