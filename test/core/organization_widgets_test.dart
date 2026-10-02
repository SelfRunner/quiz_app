import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quiz_app/core/utils/file_saver.dart';
import 'package:quiz_app/core/widgets/export_menu.dart';
import 'package:quiz_app/core/widgets/pin_button.dart';
import 'package:quiz_app/core/widgets/tag_widgets.dart';
import 'package:quiz_app/data/data_providers.dart';
import 'package:quiz_app/data/repositories/organization_repository.dart';

import '../features/search/support/org_fakes.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  FakeOrganizationRepository? org,
  FakeFileSaver? saver,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        organizationRepositoryProvider.overrideWithValue(
          org ?? FakeOrganizationRepository(),
        ),
        fileSaverProvider.overrideWithValue(saver ?? FakeFileSaver()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Controlled [TagEditor] host.
class _Host extends StatefulWidget {
  const _Host({this.suggestions});

  final List<String>? suggestions;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  List<String> tags = [];

  @override
  Widget build(BuildContext context) => TagEditor(
    tags: tags,
    suggestions: widget.suggestions,
    onChanged: (t) => setState(() => tags = t),
  );
}

List<String> _tags(WidgetTester tester) =>
    tester.state<_HostState>(find.byType(_Host)).tags;

void main() {
  group('TagEditor', () {
    testWidgets('autocompletes from suggestions (prefix first)', (
      tester,
    ) async {
      await _pump(
        tester,
        const _Host(suggestions: ['microbiology', 'biology', 'chemistry']),
      );
      await tester.enterText(find.byKey(TagEditor.fieldKey), 'bio');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tag-option-biology')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('tag-option-microbiology')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('tag-option-chemistry')), findsNothing);
      expect(find.byKey(const ValueKey('tag-create-bio')), findsOneWidget);
      // Prefix matches come before substring matches.
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('tag-option-biology'))).dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(const ValueKey('tag-option-microbiology')))
              .dy,
        ),
      );

      await tester.tap(find.byKey(const ValueKey('tag-option-biology')));
      await tester.pumpAndSettle();
      expect(_tags(tester), ['biology']);
      expect(find.text('#biology'), findsOneWidget);

      // Already-used tags are not offered again.
      await tester.enterText(find.byKey(TagEditor.fieldKey), 'bio');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tag-option-biology')), findsNothing);
    });

    testWidgets('Enter creates a new (normalized) tag; commas split', (
      tester,
    ) async {
      await _pump(tester, const _Host(suggestions: ['biology']));
      await tester.enterText(find.byKey(TagEditor.fieldKey), '  Exam  Prep ');
      await tester.pumpAndSettle();
      expect(find.text('Create "exam prep"'), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(_tags(tester), ['exam prep']);

      await tester.enterText(find.byKey(TagEditor.fieldKey), 'A,#b,');
      await tester.pumpAndSettle();
      expect(_tags(tester), ['exam prep', 'a', 'b']);

      await tester.tap(find.byTooltip('Remove a'));
      await tester.pumpAndSettle();
      expect(_tags(tester), ['exam prep', 'b']);
    });

    testWidgets('suggests tags in use by default', (tester) async {
      final org = FakeOrganizationRepository()
        ..tags.addAll(const [TagCount('physics', 3), TagCount('poetry', 1)]);
      await _pump(tester, const _Host(), org: org);
      await tester.enterText(find.byKey(TagEditor.fieldKey), 'p');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tag-option-physics')), findsOneWidget);
      expect(find.byKey(const ValueKey('tag-option-poetry')), findsOneWidget);
    });

    testWidgets('editItemTags saves through the repository', (tester) async {
      final org = FakeOrganizationRepository();
      await _pump(
        tester,
        Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () => editItemTags(
              context,
              ref,
              kind: TaggableKind.note,
              id: 'n1',
              tags: const ['old'],
            ),
            child: const Text('tags'),
          ),
        ),
        org: org,
      );
      await tester.tap(find.text('tags'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(TagEditor.fieldKey), 'new,');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tag-dialog-save')));
      await tester.pumpAndSettle();
      expect(org.calls, ['setTags:note:n1:old|new']);
    });
  });

  testWidgets('TagChips: tap runs the callback; overflow as +N', (
    tester,
  ) async {
    final tapped = <String>[];
    await _pump(
      tester,
      TagChips(tags: const ['a', 'b', 'c'], maxVisible: 2, onTap: tapped.add),
    );
    expect(find.text('#a'), findsOneWidget);
    expect(find.text('#c'), findsNothing);
    expect(find.text('+1'), findsOneWidget);
    await tester.tap(find.text('#b'));
    expect(tapped, ['b']);
    expect(tagSearchQuery('exam prep'), 'tag:"exam prep"');
    expect(tagSearchQuery('bio'), 'tag:bio');
  });

  testWidgets('TagChips default tap opens search filtered by tag', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) =>
              const Scaffold(body: TagChips(tags: ['exam prep'])),
        ),
        GoRoute(
          path: '/search',
          builder: (_, s) => Text('search ${s.uri.queryParameters['q']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('#exam prep'));
    await tester.pumpAndSettle();
    expect(find.text('search tag:"exam prep"'), findsOneWidget);
  });

  testWidgets('PinButton toggles through the repository', (tester) async {
    final org = FakeOrganizationRepository()..seed('s1', 'Bio');
    await _pump(
      tester,
      const Row(
        children: [
          PinButton.item(kind: TaggableKind.quiz, id: 'q1', pinned: false),
          PinButton.subject(subjectId: 's1', pinned: true),
        ],
      ),
      org: org,
    );
    expect(find.byTooltip('Pin'), findsOneWidget);
    expect(find.byTooltip('Unpin'), findsOneWidget);
    await tester.tap(find.byTooltip('Pin'));
    await tester.tap(find.byTooltip('Unpin'));
    await tester.pumpAndSettle();
    expect(org.calls, ['setPinned:quiz:q1:true', 'pinSubject:s1:false']);

    var value = false;
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => PinButton(
          pinned: value,
          onChanged: (v) async => setState(() => value = v),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Pin'));
    await tester.pumpAndSettle();
    expect(value, isTrue);
    expect(find.byTooltip('Unpin'), findsOneWidget);
  });

  group('ExportMenu', () {
    List<ExportItem> items(List<String> built) => [
      ExportItem(
        key: const Key('x-csv'),
        label: 'CSV',
        build: () async {
          built.add('csv');
          return ('deck.csv', Uint8List.fromList(utf8.encode('front,back')));
        },
      ),
      ExportItem(
        key: const Key('x-json'),
        label: 'JSON',
        build: () async => throw const FormatException('boom'),
      ),
    ];

    testWidgets('builds the chosen format and saves its bytes', (tester) async {
      final saver = FakeFileSaver();
      final built = <String>[];
      await _pump(tester, ExportMenu(items: items(built)), saver: saver);
      await tester.tap(find.byTooltip('Export'));
      await tester.pumpAndSettle();
      expect(find.text('CSV'), findsOneWidget);
      expect(find.text('JSON'), findsOneWidget);
      await tester.tap(find.byKey(const Key('x-csv')));
      await tester.pumpAndSettle();
      expect(built, ['csv']);
      final file = saver.saved.single;
      expect(file.name, 'deck.csv');
      expect(utf8.decode(file.bytes), 'front,back');
      expect(file.mimeType, 'text/csv');
      expect(find.text('Exported "deck.csv"'), findsOneWidget);
    });

    testWidgets('errors are reported; single item exports directly', (
      tester,
    ) async {
      final saver = FakeFileSaver()..path = '/tmp/deck.csv';
      await _pump(tester, ExportMenu(items: items([])), saver: saver);
      await tester.tap(find.byTooltip('Export'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('x-json')));
      await tester.pumpAndSettle();
      expect(saver.saved, isEmpty);
      expect(find.textContaining('Export failed'), findsOneWidget);

      await _pump(tester, ExportMenu(items: [items([]).first]), saver: saver);
      await tester.tap(find.byTooltip('Export CSV'));
      await tester.pumpAndSettle();
      expect(saver.saved.single.name, 'deck.csv');
      expect(find.text('Saved to /tmp/deck.csv'), findsOneWidget);
    });
  });

  test('mimeTypeFor', () {
    expect(mimeTypeFor('a.ZIP'), 'application/zip');
    expect(mimeTypeFor('a.tsv'), 'text/tab-separated-values');
    expect(mimeTypeFor('noext'), 'application/octet-stream');
  });
}
