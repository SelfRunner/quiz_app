import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../data/models/models.dart';
import 'deck_io.dart';
import 'quiz_io.dart';

/// Note -> Markdown with YAML front matter, Markdown -> note fields, and a
/// subject -> zip export (pure Dart, bytes / strings only; saving files is
/// the UI's job).

/// Markdown file of [note]:
///
/// ```markdown
/// ---
/// title: "Cell biology"
/// subject: "Biology"
/// tags: ["exam", "cells"]
/// created: 2026-01-01T12:00:00.000Z
/// updated: 2026-01-02T08:30:00.000Z
/// ---
///
/// <content>
/// ```
///
/// `note-image://` links are rewritten with [imageUrl] when given (e.g. to
/// relative paths inside a zip); otherwise kept as is.
String noteToMarkdown(
  Note note, {
  String? subjectTitle,
  String Function(NoteImageRef ref)? imageUrl,
}) {
  final out = StringBuffer()
    ..writeln('---')
    ..writeln('title: ${_yamlString(note.title)}');
  if (subjectTitle != null) {
    out.writeln('subject: ${_yamlString(subjectTitle)}');
  }
  out
    ..writeln('tags: [${note.tags.map(_yamlString).join(', ')}]')
    ..writeln('created: ${note.createdAt.toUtc().toIso8601String()}')
    ..writeln('updated: ${note.updatedAt.toUtc().toIso8601String()}')
    ..writeln('---')
    ..writeln();
  var body = note.contentMd;
  if (imageUrl != null) body = rewriteNoteImages(body, imageUrl);
  out.write(body);
  if (!body.endsWith('\n')) out.writeln();
  return out.toString();
}

/// Replaces every `note-image://...` URL in [markdown] with [url]`(ref)`.
String rewriteNoteImages(
  String markdown,
  String Function(NoteImageRef ref) url,
) => markdown.replaceAllMapped(_noteImageUrl, (m) {
  final ref = NoteImageRef.tryParse(m[0]!);
  return ref == null ? m[0]! : url(ref);
});

final RegExp _noteImageUrl = RegExp(
  '${NoteImageRef.scheme}://[^\\s)"\'<>\\]]+',
);

String _yamlString(String s) {
  final escaped = s
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r')
      .replaceAll('\t', r'\t');
  return '"$escaped"';
}

/// A Markdown file read back: front matter fields (when present) and the
/// body.
class MarkdownNote {
  const MarkdownNote({
    required this.title,
    required this.body,
    this.tags = const [],
    this.subject,
  });

  /// Front matter `title`, else the first `# heading`, else the
  /// file name (without extension), else 'Untitled'.
  final String title;
  final String body;
  final List<String> tags;
  final String? subject;
}

/// Parses a Markdown note with optional YAML front matter (subset: scalar
/// `key: value` pairs with plain / single / double quoted strings, and
/// `tags` as `[a, "b"]`, a block list or a comma-separated string).
MarkdownNote parseMarkdownNote(String text, {String? fileName}) {
  var source = text.startsWith('﻿') ? text.substring(1) : text;
  source = source.replaceAll('\r\n', '\n');
  final fields = <String, Object>{};
  var body = source;
  if (source.startsWith('---\n')) {
    final end = source.indexOf(
      RegExp(r'^(---|\.\.\.)[ \t]*$', multiLine: true),
      4,
    );
    if (end > 0) {
      _parseFrontMatter(source.substring(4, end), fields);
      final after = source.indexOf('\n', end);
      body = after < 0 ? '' : source.substring(after + 1);
      if (body.startsWith('\n')) body = body.substring(1);
    }
  }
  final tags = switch (fields['tags']) {
    final List<String> list => normalizeTags(list),
    final String s => normalizeTags(s.split(',')),
    _ => const <String>[],
  };
  var title = (fields['title'] as String?)?.trim() ?? '';
  if (title.isEmpty) {
    final heading = RegExp(r'^#\s+(.+)$', multiLine: true).firstMatch(body);
    title = heading?[1]?.trim() ?? '';
  }
  if (title.isEmpty && fileName != null) {
    final base = fileName.split(RegExp(r'[\\/]')).last;
    final dot = base.lastIndexOf('.');
    title = (dot > 0 ? base.substring(0, dot) : base).trim();
  }
  return MarkdownNote(
    title: title.isEmpty ? 'Untitled' : title,
    body: body,
    tags: tags,
    subject: (fields['subject'] as String?)?.trim(),
  );
}

void _parseFrontMatter(String yaml, Map<String, Object> out) {
  String? listKey;
  final list = <String>[];
  void flush() {
    if (listKey != null) out[listKey!] = List<String>.of(list);
    listKey = null;
    list.clear();
  }

  for (final line in yaml.split('\n')) {
    final item = RegExp(r'^\s*-\s+(.*)$').firstMatch(line);
    if (item != null && listKey != null) {
      list.add(_yamlScalar(item[1]!));
      continue;
    }
    final kv = RegExp(r'^([A-Za-z_][\w-]*)\s*:\s*(.*)$').firstMatch(line);
    if (kv == null) continue;
    flush();
    final key = kv[1]!.toLowerCase();
    final value = kv[2]!.trim();
    if (value.isEmpty) {
      listKey = key;
    } else if (value.startsWith('[') && value.endsWith(']')) {
      out[key] = _splitFlowList(value.substring(1, value.length - 1));
    } else {
      out[key] = _yamlScalar(value);
    }
  }
  flush();
}

List<String> _splitFlowList(String s) {
  final items = <String>[];
  final cur = StringBuffer();
  String? quote;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (quote != null) {
      cur.write(c);
      if (c == r'\' && quote == '"' && i + 1 < s.length) {
        cur.write(s[++i]);
      } else if (c == quote) {
        quote = null;
      }
    } else if (c == '"' || c == "'") {
      quote = c;
      cur.write(c);
    } else if (c == ',') {
      items.add(_yamlScalar(cur.toString().trim()));
      cur.clear();
    } else {
      cur.write(c);
    }
  }
  if (cur.toString().trim().isNotEmpty) {
    items.add(_yamlScalar(cur.toString().trim()));
  }
  return items.where((i) => i.isNotEmpty).toList();
}

String _yamlScalar(String raw) {
  final v = raw.trim();
  if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) {
    try {
      return jsonDecode(v) as String;
    } catch (_) {
      return v.substring(1, v.length - 1);
    }
  }
  if (v.length >= 2 && v.startsWith("'") && v.endsWith("'")) {
    return v.substring(1, v.length - 1).replaceAll("''", "'");
  }
  final comment = v.indexOf(' #');
  return comment >= 0 ? v.substring(0, comment).trim() : v;
}

/// File-system safe name (no path separators / reserved characters,
/// trimmed, <= 80 chars), [fallback] when nothing is left.
String safeFileName(String name, {String fallback = 'untitled'}) {
  var s = name
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  while (s.startsWith('.')) {
    s = s.substring(1).trimLeft();
  }
  if (s.length > 80) s = s.substring(0, 80).trimRight();
  return s.isEmpty ? fallback : s;
}

/// Zip of a subject: `<subject>/<note title>.md` per note (front matter,
/// see [noteToMarkdown]), plus `quizzes/<title>.json` and
/// `decks/<title>.csv` when given, and `images/<note id>-<file>` for every
/// [images] entry (keyed by `NoteImageRef.storagePath`; links to them are
/// rewritten to relative paths, other `note-image://` links are kept).
/// File names are de-duplicated with ` (2)`, ` (3)`, ...
Uint8List subjectToZip(
  Subject subject, {
  required List<Note> notes,
  List<Quiz> quizzes = const [],
  List<Deck> decks = const [],
  Map<String, Uint8List> images = const {},
}) {
  final root = safeFileName(subject.title, fallback: 'subject');
  final archive = Archive();
  final used = <String>{};
  String unique(String dir, String base, String ext) {
    var name = '$dir$base$ext';
    for (var n = 2; !used.add(name.toLowerCase()); n++) {
      name = '$dir$base ($n)$ext';
    }
    return name;
  }

  String imagePath(NoteImageRef ref) => 'images/${ref.noteId}-${ref.fileName}';

  for (final note in notes) {
    final md = noteToMarkdown(
      note,
      subjectTitle: subject.title,
      imageUrl: (ref) => images.containsKey(ref.storagePath)
          ? imagePath(ref)
          : ref.markdownUrl,
    );
    archive.addFile(
      ArchiveFile.string(unique('$root/', safeFileName(note.title), '.md'), md),
    );
  }
  for (final quiz in quizzes) {
    archive.addFile(
      ArchiveFile.string(
        unique('$root/quizzes/', safeFileName(quiz.title), '.json'),
        quizToJson(quiz),
      ),
    );
  }
  for (final deck in decks) {
    archive.addFile(
      ArchiveFile.string(
        unique('$root/decks/', safeFileName(deck.title), '.csv'),
        deckToCsv(deck),
      ),
    );
  }
  for (final MapEntry(key: path, value: bytes) in images.entries) {
    final ref = NoteImageRef.tryParse('${NoteImageRef.scheme}://$path');
    if (ref == null) continue;
    archive.addFile(ArchiveFile.bytes('$root/${imagePath(ref)}', bytes));
  }
  return ZipEncoder().encodeBytes(archive);
}
