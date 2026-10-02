import 'package:meta/meta.dart';

import '../../../data/models/deck.dart';
import '../../../study/due_queue.dart';

/// Today's cards of one deck.
@immutable
class DeckDueGroup {
  const DeckDueGroup({
    required this.deck,
    this.due = const [],
    this.fresh = const [],
    this.later = const [],
  });

  final Deck deck;

  /// Reviews due now.
  final List<DueCard> due;

  /// New cards allowed today.
  final List<DueCard> fresh;

  /// Due later today (learning steps).
  final List<DueCard> later;

  /// Cards to study right now ([due] then [fresh]).
  List<DueCard> get now => [...due, ...fresh];

  int get total => due.length + fresh.length + later.length;
}

/// Today's decks of one subject.
@immutable
class SubjectDueGroup {
  const SubjectDueGroup({required this.subjectId, required this.decks});

  final String subjectId;
  final List<DeckDueGroup> decks;

  int get dueCount => decks.fold(0, (n, d) => n + d.due.length);
  int get newCount => decks.fold(0, (n, d) => n + d.fresh.length);
  int get laterCount => decks.fold(0, (n, d) => n + d.later.length);
}

/// Groups [queue] by subject, then deck. Subjects and decks keep the order
/// in which they first appear in the study order (`queue.all`); cards keep
/// their queue order.
List<SubjectDueGroup> groupDueQueue(DueQueue queue) {
  final decks = <String, Deck>{};
  final due = <String, List<DueCard>>{};
  final fresh = <String, List<DueCard>>{};
  final later = <String, List<DueCard>>{};
  final subjectOrder = <String, List<String>>{};

  void add(Map<String, List<DueCard>> bucket, DueCard c) {
    final id = c.deck.id;
    if (!decks.containsKey(id)) {
      decks[id] = c.deck;
      subjectOrder.putIfAbsent(c.deck.subjectId, () => []).add(id);
    }
    bucket.putIfAbsent(id, () => []).add(c);
  }

  for (final c in queue.dueNow) {
    add(due, c);
  }
  for (final c in queue.newCards) {
    add(fresh, c);
  }
  for (final c in queue.laterToday) {
    add(later, c);
  }
  return [
    for (final MapEntry(key: subjectId, value: deckIds) in subjectOrder.entries)
      SubjectDueGroup(
        subjectId: subjectId,
        decks: [
          for (final id in deckIds)
            DeckDueGroup(
              deck: decks[id]!,
              due: due[id] ?? const [],
              fresh: fresh[id] ?? const [],
              later: later[id] ?? const [],
            ),
        ],
      ),
  ];
}
