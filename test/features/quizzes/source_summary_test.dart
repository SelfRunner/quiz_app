import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/features/quizzes/widgets/source_summary.dart';

void main() {
  test('legacy sources have no extra summary', () {
    expect(
      sourceSummaryOf(
        const QuizSource(
          contextText: 'text',
          youtubeUrl: 'https://youtu.be/x',
          provider: 'gemini',
          model: 'm',
        ),
      ),
      isEmpty,
    );
  });

  test('reads a list of typed sources', () {
    final entries = sourceSummaryFromJson({
      'provider': 'gemini',
      'context_text': 'ignored',
      'sources': [
        {'kind': 'note', 'label': 'Cells'},
        {'kind': 'file', 'name': 'lecture.pdf', 'mime_type': 'application/pdf'},
        {'type': 'youtube', 'url': 'https://youtu.be/abc'},
        {'kind': 'text', 'label': 'Pasted text'},
        {'kind': 'note'}, // no label: skipped
        42, // unknown shape: skipped
      ],
    });
    expect(entries.map((e) => (e.kind, e.label)), [
      ('note', 'Cells'),
      ('pdf', 'lecture.pdf'),
      ('youtube', 'https://youtu.be/abc'),
      ('text', 'Pasted text'),
    ]);
    expect(entries[1].kindLabel, 'PDF');
  });

  test('infers kinds from field names and nested summaries', () {
    final entries = sourceSummaryFromJson({
      'note_titles': ['Cells', 'Cells', ' '],
      'sources_summary': {
        'files': [
          {'file_name': 'photo.png', 'mime_type': 'image/png'},
          'notes.txt',
        ],
      },
      'model': 'x',
    });
    expect(entries.map((e) => (e.kind, e.label)), [
      ('note', 'Cells'),
      ('image', 'photo.png'),
      ('file', 'notes.txt'),
    ]);
  });
}
