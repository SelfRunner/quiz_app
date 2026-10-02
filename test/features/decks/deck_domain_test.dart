import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/features/decks/domain/bulk_cards.dart';
import 'package:quiz_app/features/decks/domain/deck_format.dart';

void main() {
  group('parseBulkCards', () {
    test('front :: back, optional hint, tabs, comments and blanks', () {
      final r = parseBulkCards(
        '# biology\n'
        'Mitochondria :: Powerhouse of the cell\n'
        '\n'
        '  H2O ::  Water :: two H, one O  \n'
        'Nucleus\tControl center\n'
        'Line one\\nline two :: Answer',
      );
      expect(r.invalidLines, isEmpty);
      expect(r.cards, const [
        CardText(front: 'Mitochondria', back: 'Powerhouse of the cell'),
        CardText(front: 'H2O', back: 'Water', hint: 'two H, one O'),
        CardText(front: 'Nucleus', back: 'Control center'),
        CardText(front: 'Line one\nline two', back: 'Answer'),
      ]);
    });

    test('reports lines without both sides (1-based)', () {
      final r = parseBulkCards(
        'ok :: fine\nno separator here\n :: missing front\nback missing ::\r\n'
        'a :: b',
      );
      expect(r.cards.map((c) => c.front), ['ok', 'a']);
      expect(r.invalidLines, [2, 3, 4]);
    });

    test('empty input', () {
      final r = parseBulkCards('  \n\n');
      expect(r.isEmpty, isTrue);
      expect(r.invalidLines, isEmpty);
    });

    test('extra separators stay in the hint', () {
      final r = parseBulkCards('a :: b :: c :: d');
      expect(r.cards.single.hint, 'c :: d');
    });
  });

  test('formatInterval', () {
    expect(formatInterval(const Duration(seconds: 30)), '<1m');
    expect(formatInterval(const Duration(minutes: 10)), '10m');
    expect(formatInterval(const Duration(hours: 5)), '5h');
    expect(formatInterval(const Duration(days: 3)), '3d');
    expect(formatInterval(const Duration(days: 45)), '1.5mo');
    expect(formatInterval(const Duration(days: 90)), '3mo');
    expect(formatInterval(const Duration(days: 365)), '1y');
    expect(formatInterval(const Duration(days: 550)), '1.5y');
  });

  test('cardsForSave drops blank cards, trims, blocks half-empty ones', () {
    const ok = Flashcard(id: 'a', front: ' Q ', back: ' A ', hint: '  ');
    const blank = Flashcard(id: 'b', front: ' ', back: '');
    const half = Flashcard(id: 'c', front: 'Q', back: ' ');
    expect(cardsForSave([ok, blank]), [
      const Flashcard(id: 'a', front: 'Q', back: 'A'),
    ]);
    expect(cardsForSave([ok, half]), isNull);
    expect(cardIssues(half), ['The back is empty.']);
  });
}
