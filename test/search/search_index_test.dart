import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/search/search_documents.dart';
import 'package:quiz_app/search/search_index.dart';
import 'package:quiz_app/search/search_models.dart';
import 'package:quiz_app/search/text_normalizer.dart';

final DateTime now = DateTime.utc(2026, 10, 1);

SearchDocument doc(
  String id,
  String title, {
  SearchItemType type = SearchItemType.note,
  String body = '',
  List<String> tags = const [],
  String? subjectId = 's1',
  int ageDays = 30,
  bool pinned = false,
}) => SearchDocument(
  type: type,
  id: id,
  title: title,
  body: body,
  tags: tags,
  subjectId: subjectId,
  updatedAt: now.subtract(Duration(days: ageDays)),
  pinned: pinned,
);

List<String> ids(List<SearchResult> results) => [for (final r in results) r.id];

String highlighted(String text, List<HighlightRange> ranges) =>
    [for (final r in ranges) text.substring(r.start, r.end)].join(',');

void main() {
  group('text normalization', () {
    test('fold diacritics, lowercase, tokenize with offsets', () {
      expect(foldWord('Équilibre'), 'equilibre');
      expect(foldWord('Straße'), 'strasse');
      expect(foldWord('Ærøskøbing'), 'aeroskobing');
      expect(foldWord('naïve'), 'naive');
      expect(foldWord('Café'), 'cafe'); // combining accent
      final tokens = tokenize('Hello, Wörld! 42x');
      expect(tokens.map((t) => t.term), ['hello', 'world', '42x']);
      expect(tokens[1].start, 7);
      expect(tokens[1].end, 12);
    });

    test('light plural stemming', () {
      expect(stem('notes'), 'note');
      expect(stem('studies'), 'study');
      expect(stem('classes'), 'class');
      expect(stem('watches'), 'watch');
      expect(stem('boxes'), 'box');
      expect(stem('class'), 'class');
      expect(stem('status'), 'status');
      expect(stem('analysis'), 'analysis');
      expect(stem('gas'), 'gas');
      expect(normalizeTerm('Équations'), 'equation');
    });

    test('plainTextFromMarkdown strips syntax', () {
      expect(
        plainTextFromMarkdown(
          '# Title\n\n- [x] **Bold** item\n> quote\n'
          '![diagram](note-image://a/b/c.png) see [docs](https://x.y)\n'
          '```dart\ncode()\n```\n| a | b |\n|---|---|\n| 1 | 2 |',
        ),
        'Title\n\nBold item\nquote\ndiagram see docs\ncode()\n a b \n 1 2',
      );
    });
  });

  group('SearchIndex', () {
    late SearchIndex index;

    setUp(() => index = SearchIndex());

    test('AND semantics over title, body and tags', () {
      index
        ..upsert(doc('a', 'Photosynthesis', body: 'Plants convert light'))
        ..upsert(doc('b', 'Cell biology', body: 'Mitochondria and light'))
        ..upsert(doc('c', 'Chemistry', tags: ['light']));
      expect(ids(index.search('light', now: now)).toSet(), {'a', 'b', 'c'});
      expect(ids(index.search('plants light', now: now)), ['a']);
      expect(index.search('plants mitochondria', now: now), isEmpty);
      expect(index.search('', now: now), isEmpty);
      expect(index.search('zzz', now: now), isEmpty);
    });

    test('diacritics, case and plurals match', () {
      index.upsert(doc('a', 'Équations différentielles'));
      expect(ids(index.search('equation', now: now)), ['a']);
      expect(ids(index.search('DIFFÉRENTIELLE', now: now)), ['a']);
    });

    test('prefix matching while typing', () {
      index
        ..upsert(doc('a', 'Photosynthesis'))
        ..upsert(doc('b', 'Photography'));
      expect(ids(index.search('photo', now: now)).toSet(), {'a', 'b'});
      expect(ids(index.search('photos', now: now)), ['a']);
      expect(index.search('p', now: now), isEmpty); // 1 char: exact only
    });

    test('ranking: title boost, exact title, phrase, recency', () {
      index
        ..upsert(doc('body', 'Notes', body: 'all about the krebs cycle'))
        ..upsert(doc('title', 'The Krebs cycle explained'))
        ..upsert(doc('exact', 'Krebs cycle', ageDays: 300))
        ..upsert(doc('apart', 'Cycle of Krebs'));
      expect(ids(index.search('krebs cycle', now: now)), [
        'exact',
        'title',
        'apart',
        'body',
      ]);

      index
        ..clear()
        ..upsert(doc('old', 'Mitosis', ageDays: 400))
        ..upsert(doc('new', 'Mitosis', ageDays: 1));
      expect(ids(index.search('mitosis', now: now)), ['new', 'old']);

      // Exact word beats a prefix expansion.
      index
        ..clear()
        ..upsert(doc('prefix', 'Cellular'))
        ..upsert(doc('exact', 'Cell'));
      expect(ids(index.search('cell', now: now)), ['exact', 'prefix']);
    });

    test('quoted phrases must match in order', () {
      index
        ..upsert(doc('a', 'x', body: 'the cell membrane is thin'))
        ..upsert(doc('b', 'y', body: 'membrane of the cell'));
      expect(ids(index.search('"cell membrane"', now: now)), ['a']);
      expect(ids(index.search('cell membrane', now: now)).toSet(), {'a', 'b'});
    });

    test('filters: type, subject, tags, pinned, archived', () {
      index
        ..upsert(doc('n', 'Algebra', tags: ['math', 'exam'], pinned: true))
        ..upsert(
          doc('q', 'Algebra quiz', type: SearchItemType.quiz, tags: ['math']),
        )
        ..upsert(doc('d', 'Algebra deck', type: SearchItemType.deck))
        ..upsert(doc('o', 'Algebra other', subjectId: 's2'))
        ..archivedSubjectIds = {'s2'};
      SearchFilters f({
        Set<SearchItemType> types = const {},
        String? subjectId,
        Set<String> tags = const {},
        bool includeArchived = true,
        bool pinnedOnly = false,
      }) => SearchFilters(
        types: types,
        subjectId: subjectId,
        tags: tags,
        includeArchived: includeArchived,
        pinnedOnly: pinnedOnly,
      );
      List<String> run(SearchFilters filters) =>
          ids(index.search('algebra', filters: filters, now: now))..sort();

      expect(run(f()), ['d', 'n', 'o', 'q']);
      expect(run(f(types: {SearchItemType.quiz, SearchItemType.deck})), [
        'd',
        'q',
      ]);
      expect(run(f(subjectId: 's2')), ['o']);
      expect(run(f(tags: {'MATH'})), ['n', 'q']);
      expect(run(f(tags: {'math', 'exam'})), ['n']);
      expect(run(f(pinnedOnly: true)), ['n']);
      expect(run(f(includeArchived: false)), ['d', 'n', 'q']);
      final archived = index.search('other', now: now).single;
      expect(archived.archived, isTrue);

      // Empty query + filters: browse by recency.
      expect(
        ids(
          index.search(
            '',
            filters: f(tags: {'math'}),
            now: now,
          ),
        )..sort(),
        ['n', 'q'],
      );
    });

    test('highlights and snippets', () {
      final body =
          '${'Lorem ipsum dolor sit amet. ' * 6}The Mitochondria is the '
          'powerhouse of the cell.\nMitochondrial DNA is inherited. '
          '${'Filler text here. ' * 10}';
      index.upsert(doc('a', 'Cell energy: mitochondria', body: body));
      final r = index.search('mitochondria', now: now).single;
      expect(highlighted(r.title, r.titleHighlights), 'mitochondria');
      expect(r.snippet, startsWith('…'));
      expect(r.snippet, endsWith('…'));
      expect(r.snippet, isNot(contains('\n')));
      expect(r.snippet.length, lessThan(200));
      expect(
        highlighted(r.snippet, r.snippetHighlights),
        'Mitochondria,Mitochondrial',
      );
      expect(r.matchedFields, {SearchField.title, SearchField.body});

      // Title-only match: snippet is the beginning of the body.
      index.upsert(doc('b', 'Ribosome', body: 'Short body.'));
      final b = index.search('ribosome', now: now).single;
      expect(b.snippet, 'Short body.');
      expect(b.snippetHighlights, isEmpty);
    });

    test('incremental upsert / remove', () {
      index.upsert(doc('a', 'Alpha'));
      expect(index.length, 1);
      index.upsert(doc('a', 'Beta'));
      expect(index.length, 1);
      expect(index.search('alpha', now: now), isEmpty);
      expect(ids(index.search('beta', now: now)), ['a']);
      expect(index.remove(SearchItemType.note, 'a'), isTrue);
      expect(index.remove(SearchItemType.note, 'a'), isFalse);
      expect(index.search('beta', now: now), isEmpty);
      // Ords are reused and postings stay consistent.
      index
        ..upsert(doc('b', 'Gamma'))
        ..upsert(doc('c', 'Gamma delta'));
      expect(ids(index.search('gamma', now: now)).toSet(), {'b', 'c'});
      // Same key, different type: separate documents.
      index.upsert(doc('b', 'Gamma', type: SearchItemType.deck));
      expect(index.search('gamma', now: now), hasLength(3));
    });

    test('subject title is resolved for results', () {
      index
        ..upsert(
          doc('s1', 'Biology', type: SearchItemType.subject, subjectId: 's1'),
        )
        ..upsert(doc('n', 'Enzymes'));
      expect(index.search('enzymes', now: now).single.subjectTitle, 'Biology');
    });

    test('benchmark: 10k items index + query', () {
      final words = [
        'cell',
        'energy',
        'protein',
        'algebra',
        'matrix',
        'vector',
        'history',
        'revolution',
        'empire',
        'poetry',
        'grammar',
        'verb',
        'molecule',
        'atom',
        'reaction',
        'equation',
        'derivative',
        'integral',
        'theorem',
        'proof',
        'climate',
        'ocean',
        'river',
        'mountain',
        'economy',
        'market',
        'trade',
        'language',
        'syntax',
        'compiler',
      ];
      String text(int seed, int n) => [
        for (var i = 0; i < n; i++)
          '${words[(seed * 7 + i * 13) % words.length]}${(seed + i) % 50}',
      ].join(' ');

      final sw = Stopwatch()..start();
      for (var i = 0; i < 10000; i++) {
        index.upsert(
          doc(
            'id$i',
            'Item $i ${text(i, 4)}',
            type: SearchItemType.values[i % SearchItemType.values.length],
            body: text(i + 1, 60),
            tags: ['t${i % 20}'],
            subjectId: 's${i % 40}',
            ageDays: i % 365,
          ),
        );
      }
      final build = sw.elapsedMilliseconds;
      sw.reset();
      const queries = [
        'cell1',
        'energy protein',
        'alg',
        'mountain river',
        'item 42',
        '"cell1 energy"',
        'theorem5 proof',
        'zzz',
        'ma',
        'compiler syntax language',
      ];
      for (final q in queries) {
        index.search(q, now: now);
      }
      final perQuery = sw.elapsedMilliseconds / queries.length;
      // Incremental update of one item.
      sw.reset();
      index.upsert(
        doc(
          'id5',
          'Renamed item',
          type: SearchItemType.values[5],
          body: text(5, 60),
        ),
      );
      final update = sw.elapsedMicroseconds;
      // ignore: avoid_print
      print(
        'search benchmark: build ${build}ms, ${perQuery.toStringAsFixed(1)} '
        'ms/query, update ${update}us',
      );
      expect(index.length, 10000);
      expect(build, lessThan(20000));
      expect(perQuery, lessThan(250));
      expect(update, lessThan(200000));
      expect(index.search('renamed', now: now).single.id, 'id5');
    });
  });
}
