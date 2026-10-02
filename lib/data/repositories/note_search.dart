import '../models/note.dart';

/// Case-insensitive search over note titles and Markdown bodies (note
/// picker).
///
/// [query] is split on whitespace; a note matches when every term occurs in
/// its title or content. Results keep the input order, except that notes
/// whose title matches all terms come first. An empty query returns [notes].
/// Lowercased text is memoized per [Note] instance (the local tables reuse
/// decoded instances), so typing over a few thousand notes stays cheap.
List<Note> searchNotes(List<Note> notes, String query) {
  final terms = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .toList();
  if (terms.isEmpty) return notes;
  final titleHits = <Note>[];
  final contentHits = <Note>[];
  for (final note in notes) {
    final text = _lowered(note);
    if (terms.every(text.title.contains)) {
      titleHits.add(note);
    } else if (terms.every(
      (t) => text.title.contains(t) || text.content.contains(t),
    )) {
      contentHits.add(note);
    }
  }
  return [...titleHits, ...contentHits];
}

/// Whether [note] matches [query] (same rules as [searchNotes]).
bool noteMatches(Note note, String query) =>
    searchNotes([note], query).isNotEmpty;

final Expando<({String title, String content})> _lowerCache = Expando();

({String title, String content}) _lowered(Note note) => _lowerCache[note] ??= (
  title: note.title.toLowerCase(),
  content: note.contentMd.toLowerCase(),
);
