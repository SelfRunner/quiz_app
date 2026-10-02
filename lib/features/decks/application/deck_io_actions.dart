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
import '../../../data/models/deck.dart';
import '../../../io/deck_io.dart';
import '../../../io/import_report.dart';
import '../../../io/note_export.dart' show safeFileName;
import '../domain/deck_format.dart';
import '../widgets/deck_import_dialog.dart';

/// File extensions offered when importing cards.
const List<String> kDeckImportExtensions = ['csv', 'tsv', 'txt'];

/// CSV (`front,back,hint`) and Anki TSV exports of [deck].
List<ExportItem> deckExportItems(Deck deck) {
  final base = safeFileName(deck.title, fallback: 'deck');
  return [
    ExportItem(
      key: const Key('export-deck-csv'),
      label: 'CSV (.csv)',
      icon: Icons.table_chart_outlined,
      build: () async =>
          ('$base.csv', Uint8List.fromList(utf8.encode(deckToCsv(deck)))),
    ),
    ExportItem(
      key: const Key('export-deck-anki'),
      label: 'Anki (.txt)',
      icon: Icons.style_outlined,
      build: () async => (
        '$base (Anki).txt',
        Uint8List.fromList(utf8.encode(deckToAnkiTsv(deck))),
      ),
    ),
  ];
}

/// A confirmed import: the file name and the parsed cards.
typedef DeckImport = ({String fileName, ImportResult<Flashcard> result});

/// Picks a CSV / TSV file, parses it (`importDeckText`) and shows the
/// preview with every skipped row. Returns the import when the user
/// confirms, null when cancelled or nothing could be read.
Future<DeckImport?> pickDeckImport(
  BuildContext context,
  WidgetRef ref, {
  String? target,
}) async {
  final OpenedFile? file;
  try {
    file = await ref
        .read(fileOpenerProvider)
        .pick(extensions: kDeckImportExtensions, dialogTitle: 'Import cards');
  } catch (e) {
    if (context.mounted) showErrorSnackBar(context, e, prefix: 'Import failed');
    return null;
  }
  if (file == null || !context.mounted) return null;
  final result = importDeckText(
    file.text,
    newId: ref.read(idGeneratorProvider),
  );
  final ok = await showDeckImportPreview(
    context,
    fileName: file.name,
    result: result,
    target: target,
  );
  return ok ? (fileName: file.name, result: result) : null;
}

/// Imports cards from a file and appends them to [deck] (owner).
Future<void> importCardsIntoDeck(
  BuildContext context,
  WidgetRef ref,
  Deck deck,
) async {
  final picked = await pickDeckImport(context, ref, target: deck.title);
  if (picked == null || !context.mounted) return;
  final cards = picked.result.items;
  try {
    final repo = ref.read(deckRepositoryProvider);
    final current = await repo.getById(deck.id) ?? deck;
    final used = {for (final c in current.cards) c.id};
    final newId = ref.read(idGeneratorProvider);
    await repo.update(
      current.copyWith(
        cards: [
          ...current.cards,
          for (final c in cards)
            used.add(c.id) ? c : c.copyWith(id: _freshId(newId, used)),
        ],
      ),
    );
    if (context.mounted) {
      showAppSnackBar(context, 'Imported ${plural(cards.length, 'card')}');
    }
  } catch (e) {
    if (context.mounted) showErrorSnackBar(context, e, prefix: 'Import failed');
  }
}

/// Imports a file as a new deck in [subjectId] (optionally [noteId]),
/// titled after the file, and opens it.
Future<void> importNewDeck(
  BuildContext context,
  WidgetRef ref, {
  required String subjectId,
  String? noteId,
}) async {
  final picked = await pickDeckImport(context, ref);
  if (picked == null || !context.mounted) return;
  final name = picked.fileName;
  final dot = name.lastIndexOf('.');
  final title = (dot > 0 ? name.substring(0, dot) : name).trim();
  try {
    final deck = await ref
        .read(deckRepositoryProvider)
        .create(
          subjectId: subjectId,
          noteId: noteId,
          title: title.isEmpty ? 'Imported deck' : title,
          cards: picked.result.items,
        );
    if (!context.mounted) return;
    showAppSnackBar(
      context,
      'Imported ${plural(picked.result.items.length, 'card')}',
    );
    await GoRouter.maybeOf(context)?.push(AppRoutes.deck(deck.id));
  } catch (e) {
    if (context.mounted) showErrorSnackBar(context, e, prefix: 'Import failed');
  }
}

String _freshId(String Function() newId, Set<String> used) {
  var id = newId();
  while (!used.add(id)) {
    id = newId();
  }
  return id;
}
