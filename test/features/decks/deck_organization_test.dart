import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/core/utils/file_opener.dart';
import 'package:quiz_app/core/utils/file_saver.dart';
import 'package:quiz_app/core/widgets/tag_widgets.dart';
import 'package:quiz_app/data/data_providers.dart';
import 'package:quiz_app/data/repositories/organization_repository.dart';
import 'package:quiz_app/features/decks/widgets/deck_import_dialog.dart';
import 'package:quiz_app/features/decks/widgets/deck_list_section.dart';
import 'package:quiz_app/io/deck_io.dart';

import '../quizzes/support/fakes.dart';
import '../search/support/org_fakes.dart';
import 'support/deck_fakes.dart';

class _Env extends DeckTestEnv {
  _Env() {
    org.onItem = (kind, id, {tags, pinned}) {
      final d = decks.rows[id]!;
      decks.put(d.copyWith(tags: tags ?? d.tags, pinned: pinned ?? d.pinned));
    };
  }

  final org = FakeOrganizationRepository();
  final opener = FakeFileOpener();
  final saver = FakeFileSaver();

  @override
  List<Override> get extraOverrides => [
    ...super.extraOverrides,
    organizationRepositoryProvider.overrideWithValue(org),
    fileOpenerProvider.overrideWithValue(opener),
    fileSaverProvider.overrideWithValue(saver),
  ];
}

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

const _csv =
    'front,back,hint\n'
    'Q1,A1,\n'
    ',no front\n'
    'Q3,\n'
    'Q4,A4,h4\n';

void main() {
  group('deck import', () {
    testWidgets('preview reports skipped rows by line, then appends', (
      tester,
    ) async {
      _tall(tester);
      final env = _Env();
      env.decks.put(deck('d1', [card('c1', 'Old', 'Card')], title: 'Cells'));
      env.opener.text('cards.csv', _csv);
      await tester.pumpWidget(env.deckApp('/decks/d1'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('deck-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deck-import-cards')));
      await tester.pumpAndSettle();

      expect(env.opener.lastExtensions, ['csv', 'tsv', 'txt']);
      expect(find.byType(DeckImportPreviewDialog), findsOneWidget);
      expect(find.text('2 cards ready · 2 rows skipped'), findsOneWidget);
      expect(find.text('Line 3: Missing front.'), findsOneWidget);
      expect(find.text('Line 4: Missing back.'), findsOneWidget);
      expect(find.text('Q1'), findsOneWidget);
      expect(find.text('Q4'), findsOneWidget);

      await tester.tap(find.byKey(DeckImportPreviewDialog.confirmKey));
      await tester.pumpAndSettle();
      final saved = env.decks.updates.last;
      expect(saved.cards.map((c) => c.front), ['Old', 'Q1', 'Q4']);
      expect(saved.cards.last.hint, 'h4');
      expect(saved.cards.map((c) => c.id).toSet(), hasLength(3));
      expect(find.text('Imported 2 cards'), findsOneWidget);
    });

    testWidgets('cancel or an empty file changes nothing', (tester) async {
      _tall(tester);
      final env = _Env();
      env.decks.put(deck('d1', [card('c1', 'Old', 'Card')]));
      env.opener.text('bad.csv', 'front,back\nonly front,\n');
      await tester.pumpWidget(env.deckApp('/decks/d1'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deck-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deck-import-cards')));
      await tester.pumpAndSettle();
      expect(find.text('0 cards ready · 1 row skipped'), findsOneWidget);
      final confirm = tester.widget<FilledButton>(
        find.byKey(DeckImportPreviewDialog.confirmKey),
      );
      expect(confirm.onPressed, isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(env.decks.updates, isEmpty);

      // Picker cancelled: no dialog.
      env.opener.next = null;
      await tester.tap(find.byKey(const Key('deck-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deck-import-cards')));
      await tester.pumpAndSettle();
      expect(find.byType(DeckImportPreviewDialog), findsNothing);
    });

    testWidgets('Anki TSV import in the editor adds cards to save', (
      tester,
    ) async {
      _tall(tester);
      final env = _Env();
      env.decks.put(deck('d1', [card('c1', 'Old', 'Card')]));
      env.opener.text(
        'anki.txt',
        '#separator:tab\n#html:true\nFront<br>two\tBack &amp; more\n',
      );
      await tester.pumpWidget(env.deckApp('/decks/d1/edit'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deck-edit-import')));
      await tester.pumpAndSettle();
      expect(find.text('1 card ready'), findsOneWidget);
      await tester.tap(find.byKey(DeckImportPreviewDialog.confirmKey));
      await tester.pumpAndSettle();
      expect(env.decks.updates, isEmpty); // not saved yet
      await tester.tap(find.byKey(const Key('save-deck')));
      await tester.pumpAndSettle();
      final saved = env.decks.updates.single;
      expect(saved.cards.last.front, 'Front\ntwo');
      expect(saved.cards.last.back, 'Back & more');
    });
  });

  group('deck export', () {
    testWidgets('CSV and Anki exports produce the expected bytes', (
      tester,
    ) async {
      _tall(tester);
      final env = _Env();
      final d = env.decks.put(
        deck('d1', [
          card('c1', 'Q, "1"', 'A1', hint: 'h'),
          card('c2', 'Q2', 'line\nbreak'),
        ], title: 'Cell cards').copyWith(tags: ['bio']),
      );
      await tester.pumpWidget(env.deckApp('/decks/d1'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Export'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-deck-csv')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Export'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-deck-anki')));
      await tester.pumpAndSettle();

      final [csv, anki] = env.saver.saved;
      expect(csv.name, 'Cell cards.csv');
      expect(utf8.decode(csv.bytes), deckToCsv(d));
      expect(utf8.decode(csv.bytes), startsWith('front,back,hint'));
      expect(anki.name, 'Cell cards (Anki).txt');
      expect(utf8.decode(anki.bytes), deckToAnkiTsv(d));
      expect(utf8.decode(anki.bytes), contains('#tags:bio'));
      expect(anki.mimeType, 'text/plain');
    });

    testWidgets('shared decks can be exported but not pinned', (tester) async {
      _tall(tester);
      final env = _Env();
      env.decks.put(deck('d1', [card('c1', 'Q', 'A')], owner: 'other'));
      await tester.pumpWidget(env.deckApp('/decks/d1'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Export'), findsOneWidget);
      expect(find.byTooltip('Pin'), findsNothing);
      expect(find.byKey(const Key('deck-tags-button')), findsNothing);
    });
  });

  group('deck organization', () {
    testWidgets('pin and tags from the detail screen', (tester) async {
      _tall(tester);
      final env = _Env();
      env.org.tags.add(const TagCount('biology', 2));
      env.decks.put(deck('d1', [card('c1', 'Q', 'A')]));
      await tester.pumpWidget(env.deckApp('/decks/d1'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Pin'));
      await tester.pumpAndSettle();
      expect(env.org.calls, ['setPinned:deck:d1:true']);
      expect(find.byTooltip('Unpin'), findsOneWidget);

      await tester.tap(find.byKey(const Key('deck-tags-button')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(TagEditor.fieldKey), 'bio');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tag-option-biology')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tag-dialog-save')));
      await tester.pumpAndSettle();
      expect(env.org.calls.last, 'setTags:deck:d1:biology');
      expect(find.byKey(const ValueKey('tag-chip-biology')), findsOneWidget);
    });

    testWidgets('tags edited in the deck editor are saved', (tester) async {
      _tall(tester);
      final env = _Env();
      env.decks.put(deck('d1', [card('c1', 'Q', 'A')]).copyWith(tags: ['old']));
      await tester.pumpWidget(env.deckApp('/decks/d1/edit'));
      await tester.pumpAndSettle();
      expect(find.text('#old'), findsOneWidget);
      await tester.enterText(find.byKey(TagEditor.fieldKey), 'New Tag,');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-deck')));
      await tester.pumpAndSettle();
      expect(env.decks.updates.single.tags, ['old', 'new tag']);
    });

    testWidgets('DeckListSection lists pinned decks first with tags', (
      tester,
    ) async {
      _tall(tester);
      final env = _Env();
      env.decks
        ..put(deck('d1', [card('c1', 'Q', 'A')], title: 'Alpha'))
        ..put(
          deck('d2', [
            card('c2', 'Q', 'A'),
          ], title: 'Beta').copyWith(pinned: true, tags: ['exam']),
        );
      await tester.pumpWidget(
        env.deckApp(
          '/',
          home: const Scaffold(
            body: SingleChildScrollView(
              child: DeckListSection(subjectId: 's1'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final beta = tester.getTopLeft(find.byKey(const ValueKey('deck-row-d2')));
      final alpha = tester.getTopLeft(
        find.byKey(const ValueKey('deck-row-d1')),
      );
      expect(beta.dy, lessThan(alpha.dy));
      expect(find.byKey(const ValueKey('deck-pinned-d2')), findsOneWidget);
      expect(find.text('#exam'), findsOneWidget);
      expect(pinnedFirst(env.decks.live).first.id, 'd2');
    });

    testWidgets('DeckListSection imports a file as a new deck', (tester) async {
      _tall(tester);
      final env = _Env();
      env.opener.text('Spanish verbs.csv', 'ser,to be\nestar,to be (state)\n');
      await tester.pumpWidget(
        env.deckApp(
          '/',
          home: const Scaffold(
            body: SingleChildScrollView(
              child: DeckListSection(subjectId: 's1'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deck-import')));
      await tester.pumpAndSettle();
      expect(find.text('2 cards ready'), findsOneWidget);
      await tester.tap(find.byKey(DeckImportPreviewDialog.confirmKey));
      await tester.pumpAndSettle();
      final created = env.decks.created.single;
      expect(created.title, 'Spanish verbs');
      expect(created.subjectId, 's1');
      expect(created.cards.map((c) => c.front), ['ser', 'estar']);
    });
  });

  test('OpenedFile.text drops a BOM', () {
    final f = OpenedFile('a.csv', utf8.encode('﻿front,back'));
    expect(f.text, 'front,back');
    expect(userId, isNotEmpty);
  });
}
