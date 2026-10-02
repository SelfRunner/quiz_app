import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/io/csv.dart';
import 'package:quiz_app/io/deck_io.dart';
import 'package:quiz_app/io/import_report.dart';
import 'package:quiz_app/io/markdown_blocks.dart';
import 'package:quiz_app/io/note_export.dart';
import 'package:quiz_app/io/quiz_io.dart';

final DateTime t0 = DateTime.utc(2026, 1, 2, 3, 4, 5);

String Function() seqIds() {
  var n = 0;
  return () => 'new-${++n}';
}

Note note({
  String id = 'n1',
  String title = 'Cell biology',
  String content = '# Cells\n\nBody',
  List<String> tags = const ['exam', 'cells'],
}) => Note(
  id: id,
  subjectId: 's1',
  ownerId: 'u',
  title: title,
  contentMd: content,
  tags: tags,
  createdAt: t0,
  updatedAt: t0,
);

final Quiz sampleQuiz = Quiz(
  id: 'quiz-1',
  subjectId: 's1',
  noteId: 'n1',
  ownerId: 'u',
  title: 'Biology "basics"',
  description: 'Line 1\nLine 2',
  tags: const ['bio'],
  pinned: true,
  source: const QuizSource(provider: 'gemini', model: 'm'),
  questions: const [
    Question(
      id: 'q1',
      type: QuestionType.mcqSingle,
      prompt: 'Powerhouse of the cell?',
      options: ['Ribosome', 'Mito|chondria', r'Back\slash'],
      correctIndices: [1],
      explanation: 'Makes ATP, "energy"',
    ),
    Question(
      id: 'q2',
      type: QuestionType.mcqMulti,
      prompt: 'Primes, with a\nnewline',
      options: ['2', '3', '4'],
      correctIndices: [0, 1],
    ),
    Question(
      id: 'q3',
      type: QuestionType.trueFalse,
      prompt: 'DNA is a protein',
      options: ['True', 'False'],
      correctIndices: [1],
    ),
    Question(
      id: 'q4',
      type: QuestionType.shortAnswer,
      prompt: 'Symbol of gold',
      answerText: 'Au',
    ),
  ],
  createdAt: t0,
  updatedAt: t0,
);

void main() {
  group('csv codec', () {
    test('round-trips quotes, delimiters, newlines; reports lines', () {
      final rows = [
        ['a', 'b,c', 'say "hi"'],
        ['multi\nline', ' padded ', ''],
        ['x', 'y', 'z'],
      ];
      final text = encodeCsv(rows);
      expect(text, startsWith('a,"b,c","say ""hi"""\r\n'));
      final parsed = decodeCsv(text);
      expect(parsed.map((r) => r.fields), rows);
      expect(parsed.map((r) => r.line), [1, 2, 4]);
      expect(decodeCsv('﻿a;b\n', delimiter: ';').single.fields, ['a', 'b']);
      expect(
        () => decodeCsv('a,"open\nb'),
        throwsA(isA<CsvFormatException>().having((e) => e.line, 'line', 1)),
      );
    });
  });

  group('notes -> markdown', () {
    test('front matter and round trip', () {
      final n = note(title: 'Title: "quoted" \\ ok');
      final mdText = noteToMarkdown(n, subjectTitle: 'Biology');
      expect(
        mdText,
        '---\n'
        'title: "Title: \\"quoted\\" \\\\ ok"\n'
        'subject: "Biology"\n'
        'tags: ["exam", "cells"]\n'
        'created: 2026-01-02T03:04:05.000Z\n'
        'updated: 2026-01-02T03:04:05.000Z\n'
        '---\n'
        '\n'
        '# Cells\n\nBody\n',
      );
      final back = parseMarkdownNote(mdText);
      expect(back.title, n.title);
      expect(back.tags, ['exam', 'cells']);
      expect(back.subject, 'Biology');
      expect(back.body, '# Cells\n\nBody\n');
    });

    test('parse: block tag lists, no front matter, file name fallback', () {
      final parsed = parseMarkdownNote(
        "---\ntitle: 'It''s'\ntags:\n  - One\n  - two # c\n---\nText",
      );
      expect(parsed.title, "It's");
      expect(parsed.tags, ['one', 'two']);
      expect(parsed.body, 'Text');
      expect(parseMarkdownNote('# Heading\nx').title, 'Heading');
      expect(
        parseMarkdownNote('x', fileName: 'dir/My note.md').title,
        'My note',
      );
      expect(parseMarkdownNote('').title, 'Untitled');
      expect(parseMarkdownNote('---\ntags: a, B\n---\n').tags, ['a', 'b']);
    });

    test('image links can be rewritten', () {
      final n = note(content: '![x](note-image://u/n1/abc.png) and text');
      expect(
        noteToMarkdown(n, imageUrl: (ref) => 'images/${ref.fileName}'),
        contains('![x](images/abc.png) and text'),
      );
    });

    test('subject -> zip of markdown files (+ quizzes, decks, images)', () {
      final subject = Subject(
        id: 's1',
        ownerId: 'u',
        title: 'Bio/Chem',
        createdAt: t0,
        updatedAt: t0,
      );
      final bytes = subjectToZip(
        subject,
        notes: [
          note(content: '![a](note-image://u/n1/img.png)'),
          note(id: 'n2', content: 'second'),
          note(id: 'n3', title: 'a/b:c', content: 'third'),
        ],
        quizzes: [sampleQuiz],
        decks: [
          Deck(
            id: 'd',
            subjectId: 's1',
            ownerId: 'u',
            title: 'Deck',
            cards: const [Flashcard(id: 'c', front: 'F', back: 'B')],
            createdAt: t0,
            updatedAt: t0,
          ),
        ],
        images: {
          'u/n1/img.png': Uint8List.fromList([1, 2, 3]),
        },
      );
      final archive = ZipDecoder().decodeBytes(bytes);
      final names = archive.files.map((f) => f.name).toList();
      expect(names, [
        'Bio Chem/Cell biology.md',
        'Bio Chem/Cell biology (2).md',
        'Bio Chem/a b c.md',
        'Bio Chem/quizzes/Biology basics.json',
        'Bio Chem/decks/Deck.csv',
        'Bio Chem/images/n1-img.png',
      ]);
      final first = utf8.decode(archive.files.first.content as List<int>);
      expect(first, contains('![a](images/n1-img.png)'));
      expect(archive.files.last.content, [1, 2, 3]);
    });

    test('safeFileName', () {
      expect(safeFileName('  ..a/b\\c?  '), 'a b c');
      expect(safeFileName(''), 'untitled');
      expect(safeFileName('x' * 100).length, 80);
    });
  });

  group('quizzes', () {
    test('JSON export is lossless', () {
      final text = quizToJson(sampleQuiz);
      final json = jsonDecode(text) as Map<String, dynamic>;
      expect(json['format'], 'quiz_app.quiz');
      expect(json['version'], 1);
      final quiz = json['quiz'] as Map<String, dynamic>;
      expect(quiz.containsKey('owner_id'), isFalse);
      final restored = Quiz.fromJson({
        ...quiz,
        'owner_id': 'u',
        'subject_id': 's1',
        'note_id': 'n1',
      });
      expect(restored, sampleQuiz);

      final imported = importQuizJson(text, newId: seqIds());
      expect(imported.hasErrors, isFalse);
      expect(imported.items, sampleQuiz.questions);
      expect(imported.title, sampleQuiz.title);
      expect(imported.description, sampleQuiz.description);
      expect(imported.tags, ['bio']);
      final fresh = importQuizJson(text, newId: seqIds(), newIds: true);
      expect(fresh.items.map((q) => q.id), [
        'new-1',
        'new-2',
        'new-3',
        'new-4',
      ]);
    });

    test('JSON import: bare list, camelCase, validation paths, bad JSON', () {
      final result = importQuizJson(
        jsonEncode([
          {
            'type': 'mcq_single',
            'prompt': 'Q',
            'options': ['a', 'b'],
            'correctIndices': [0],
          },
          {
            'type': 'mcq_single',
            'prompt': 'Q2',
            'options': ['a', 'b'],
            'correct_indices': [0, 1],
          },
          {'type': 'banana', 'prompt': 'Q3'},
          'oops',
          {'type': 'short_answer', 'prompt': 'Q4', 'answerText': 'A'},
        ]),
        newId: seqIds(),
      );
      expect(result.items.map((q) => q.prompt), ['Q', 'Q4']);
      expect(result.errors.map((e) => e.field), [
        'questions[1]',
        'questions[2]',
        'questions[3]',
      ]);
      expect(result.errors[1].message, contains('banana'));

      final bad = importQuizJson('{\n  "questions": [\n    {,]\n}');
      expect(bad.errors.single.line, 3);
      expect(importQuizJson('{"format":"other","quiz":{}}').hasErrors, isTrue);
      expect(importQuizJson('{"title":"x"}').errors.single.field, 'questions');
    });

    test('CSV export / import round trip', () {
      final text = quizToCsv(sampleQuiz);
      final lines = text.split('\r\n');
      expect(lines.first, 'type,prompt,options,correct,answer,explanation');
      expect(
        lines[1],
        r'mcq_single,Powerhouse of the cell?,Ribosome|Mito\|chondria|Back\\slash,2,,"Makes ATP, ""energy"""',
      );
      final imported = importQuizCsv(text, newId: seqIds());
      expect(imported.errors, isEmpty);
      expect(imported.warnings, isEmpty);
      expect(
        imported.items.map((q) => q.copyWith(id: '')),
        sampleQuiz.questions.map((q) => q.copyWith(id: '')),
      );
      expect(imported.items.map((q) => q.id), [
        'new-1',
        'new-2',
        'new-3',
        'new-4',
      ]);
    });

    test('CSV import: lenient input, error report with line numbers', () {
      const csv =
          'Question;Choices;Correct answer;Type\n'
          'Capital of France?;Paris|Rome;A;\n'
          '\n'
          'Pick evens;1|2|4;2|3;multi\n'
          'Sky is blue;;true;tf\n'
          'Zero based;a|b;0;\n'
          'Bad index;a|b;5;\n'
          ';a|b;1;\n'
          'Odd type;a|b;1;weird\n'
          'By text;Red|Green;green;\n'
          'No answer;;;short\n';
      final r = importQuizCsv(csv, newId: seqIds());
      expect(
        r.items.map((q) => (q.prompt, q.type, q.correctIndices.join('|'))),
        [
          ('Capital of France?', QuestionType.mcqSingle, '0'),
          ('Pick evens', QuestionType.mcqMulti, '1|2'),
          ('Sky is blue', QuestionType.trueFalse, '0'),
          ('Zero based', QuestionType.mcqSingle, '0'),
          ('By text', QuestionType.mcqSingle, '1'),
        ],
      );
      expect(r.warnings.single.line, 6);
      expect(r.errors.map((e) => e.line), [7, 8, 9, 11]);
      expect(r.report, contains('Error: line 7'));
      expect(importQuizCsv('').warnings, isNotEmpty);
      expect(importQuizCsv('"unterminated').errors.single.line, 1);
    });
  });

  group('decks', () {
    final deck = Deck(
      id: 'd',
      subjectId: 's',
      ownerId: 'u',
      title: 'D',
      tags: const ['bio stuff', 'exam'],
      cards: const [
        Flashcard(id: 'c1', front: 'A <b> & "c"', back: 'line1\nline2'),
        Flashcard(id: 'c2', front: 'Tab\there', back: 'x, y', hint: 'h'),
      ],
      createdAt: t0,
      updatedAt: t0,
    );

    test('CSV round trip', () {
      final text = deckToCsv(deck);
      expect(text, startsWith('front,back,hint\r\n'));
      final r = importDeckText(text, newId: seqIds());
      expect(r.errors, isEmpty);
      expect(
        r.items.map((c) => (c.front, c.back, c.hint)),
        deck.cards.map((c) => (c.front, c.back, c.hint)),
      );
      expect(r.items.map((c) => c.id), ['new-1', 'new-2']);
    });

    test('Anki TSV export / import', () {
      final text = deckToAnkiTsv(deck);
      final lines = text.split('\n');
      expect(lines.take(4), [
        '#separator:tab',
        '#html:true',
        '#columns:Front\tBack\tHint',
        '#tags:bio_stuff exam',
      ]);
      expect(lines[4], 'A &lt;b&gt; &amp; &quot;c&quot;\tline1<br>line2\t');
      final r = importDeckText(text, newId: seqIds());
      expect(r.errors, isEmpty);
      expect(r.items.first.front, 'A <b> & "c"');
      expect(r.items.first.back, 'line1\nline2');
      expect(r.items.last.front, 'Tab    here');
      expect(r.items.last.hint, 'h');
    });

    test('import errors carry line numbers', () {
      const tsv = 'front\tback\nq1\ta1\n\nq2\t\n\ta3\nq4\ta4\textra\tmore\n';
      final r = importDeckTsv(tsv, newId: seqIds());
      expect(r.items.map((c) => c.front), ['q1', 'q4']);
      expect(r.errors, const [
        ImportIssue('Missing back.', line: 4),
        ImportIssue('Missing front.', line: 5),
      ]);
      expect(r.warnings.single.line, 6);

      final csv = importDeckCsv('"Front","Back"\n#tag,x\n', newId: seqIds());
      expect(csv.items.single.front, '#tag');
      expect(importDeckCsv('').warnings, isNotEmpty);
    });
  });

  group('markdown -> blocks', () {
    test('headings, paragraphs, spans, lists, code, quotes, tables', () {
      final blocks = markdownToBlocks(
        '# Title\n\n'
        'Some **bold** and *it* with `code` and [link](https://x.y).\n\n'
        '- one\n'
        '  - nested\n'
        '- [x] done\n\n'
        '3. third\n'
        '4. fourth\n\n'
        '```dart\nvoid main() {}\n```\n\n'
        '> quoted\n\n'
        '| a | b |\n|---|---|\n| 1 | **2** |\n\n'
        '---\n\n'
        '![diagram](note-image://u/n/x.png)\n\n'
        r'$$'
        '\nE = mc^2\n'
        r'$$'
        '\n',
      );
      expect(blocks[0], isA<MdHeading>());
      expect((blocks[0] as MdHeading).level, 1);
      final p = blocks[1] as MdParagraph;
      expect(p.spans, const [
        MdSpan('Some '),
        MdSpan('bold', bold: true),
        MdSpan(' and '),
        MdSpan('it', italic: true),
        MdSpan(' with '),
        MdSpan('code', code: true),
        MdSpan(' and '),
        MdSpan('link', link: 'https://x.y'),
        MdSpan('.'),
      ]);
      final items = blocks.whereType<MdListItem>().toList();
      expect(
        items.map((i) => (i.text, i.depth, i.ordered, i.number, i.checked)),
        [
          ('one', 0, false, null, null),
          ('nested', 1, false, null, null),
          ('done', 0, false, null, true),
          ('third', 0, true, 3, null),
          ('fourth', 0, true, 4, null),
        ],
      );
      final code = blocks.whereType<MdCode>().single;
      expect(code.text, 'void main() {}');
      expect(code.language, 'dart');
      final quote = blocks.whereType<MdQuote>().single;
      expect((quote.children.single as MdParagraph).text, 'quoted');
      final table = blocks.whereType<MdTable>().single;
      expect(table.header.map(spansText), ['a', 'b']);
      expect(table.rows.single.map(spansText), ['1', '2']);
      expect(table.rows.single[1].single.bold, isTrue);
      expect(blocks.whereType<MdRule>(), hasLength(1));
      final image = blocks.whereType<MdImage>().single;
      expect((image.url, image.alt), ('note-image://u/n/x.png', 'diagram'));
      expect(blocks.last, isA<MdMath>());
      expect((blocks.last as MdMath).tex, 'E = mc^2');
    });
  });
}
