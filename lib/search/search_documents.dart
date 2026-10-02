import '../data/models/models.dart';
import 'search_models.dart';

/// Converts the app's models to [SearchDocument]s (pure Dart).

SearchDocument subjectDocument(Subject s) => SearchDocument(
  type: SearchItemType.subject,
  id: s.id,
  title: s.title,
  body: s.description ?? '',
  subjectId: s.id,
  ownerId: s.ownerId,
  updatedAt: s.updatedAt,
  pinned: s.pinned,
);

/// Title + content (Markdown syntax stripped, see [plainTextFromMarkdown]).
SearchDocument noteDocument(Note n) => SearchDocument(
  type: SearchItemType.note,
  id: n.id,
  title: n.title,
  body: plainTextFromMarkdown(n.contentMd),
  tags: n.tags,
  subjectId: n.subjectId,
  noteId: n.id,
  ownerId: n.ownerId,
  updatedAt: n.updatedAt,
  pinned: n.pinned,
);

/// Title + description + question prompts, options and expected answers.
SearchDocument quizDocument(Quiz q) => SearchDocument(
  type: SearchItemType.quiz,
  id: q.id,
  title: q.title,
  body: [
    if (q.description case final d? when d.isNotEmpty) d,
    for (final question in q.questions) ...[
      question.prompt,
      ...question.options,
      if (question.answerText case final a? when a.isNotEmpty) a,
    ],
  ].join('\n'),
  tags: q.tags,
  subjectId: q.subjectId,
  noteId: q.noteId,
  ownerId: q.ownerId,
  updatedAt: q.updatedAt,
  pinned: q.pinned,
);

/// Title + description + card fronts, backs and hints.
SearchDocument deckDocument(Deck d) => SearchDocument(
  type: SearchItemType.deck,
  id: d.id,
  title: d.title,
  body: [
    if (d.description case final x? when x.isNotEmpty) x,
    for (final card in d.cards) ...[
      card.front,
      card.back,
      if (card.hint case final h? when h.isNotEmpty) h,
    ],
  ].join('\n'),
  tags: d.tags,
  subjectId: d.subjectId,
  noteId: d.noteId,
  ownerId: d.ownerId,
  updatedAt: d.updatedAt,
  pinned: d.pinned,
);

/// File name + extracted text.
SearchDocument attachmentDocument(Attachment a) => SearchDocument(
  type: SearchItemType.attachment,
  id: a.id,
  title: a.name,
  body: a.extractedText ?? '',
  subjectId: a.subjectId,
  ownerId: a.ownerId,
  updatedAt: a.updatedAt,
);

/// Chat title only. [subjectId] = the scope's subject when known
/// (subject scopes use their id).
SearchDocument chatDocument(Chat c, {String? subjectId, String? noteId}) =>
    SearchDocument(
      type: SearchItemType.chat,
      id: c.id,
      title: c.title,
      subjectId:
          subjectId ??
          (c.scopeType == ChatScopeType.subject ? c.scopeId : null),
      noteId: noteId ?? (c.scopeType == ChatScopeType.note ? c.scopeId : null),
      ownerId: c.ownerId,
      updatedAt: c.updatedAt,
    );

final RegExp _mdImage = RegExp(r'!\[([^\]]*)\]\([^)]*\)');
final RegExp _mdLink = RegExp(r'\[([^\]]*)\]\([^)]*\)');
final RegExp _mdLinePrefix = RegExp(
  r'^[ \t]*(?:#{1,6}[ \t]+|>[ \t]?|[-*+][ \t]+(?:\[[ xX]\][ \t]+)?|\d+[.)][ \t]+)',
  multiLine: true,
);
final RegExp _mdRule = RegExp(
  r'^[ \t]*(?:[-*_][ \t]*){3,}$\n?',
  multiLine: true,
);
final RegExp _mdFence = RegExp(
  r'^[ \t]*(?:```|~~~)[^\n]*$\n?',
  multiLine: true,
);
final RegExp _mdTableSep = RegExp(
  r'^[ \t]*\|?[ \t:|-]+\|[ \t:|-]*$\n?',
  multiLine: true,
);
final RegExp _mdEmphasis = RegExp(r'(\*\*|__|\*|~~|`)');
final RegExp _mdPipes = RegExp(r'[ \t]*\|[ \t]*');
final RegExp _blankRuns = RegExp(r'\n{3,}');

/// Readable plain text of a Markdown body (for search and snippets):
/// images -> alt text, links -> their text, heading / list / quote markers,
/// fences, rules, emphasis and table pipes removed. Not a full renderer.
String plainTextFromMarkdown(String markdown) {
  if (markdown.isEmpty) return '';
  return markdown
      .replaceAllMapped(_mdImage, (m) => m[1]!)
      .replaceAllMapped(_mdLink, (m) => m[1]!)
      .replaceAll(_mdFence, '')
      .replaceAll(_mdRule, '')
      .replaceAll(_mdTableSep, '')
      .replaceAll(_mdLinePrefix, '')
      .replaceAll(_mdEmphasis, '')
      .replaceAll(_mdPipes, ' ')
      .replaceAll(_blankRuns, '\n\n')
      .trim();
}
