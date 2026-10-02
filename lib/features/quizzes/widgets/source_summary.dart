import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../data/models/quiz_source.dart';

/// One source used to generate a quiz (a note, file, YouTube video, pasted
/// text, ...), for display only.
@immutable
class SourceSummaryEntry {
  const SourceSummaryEntry({
    required this.kind,
    required this.label,
    this.detail,
  });

  /// Normalized kind: `note`, `file`, `pdf`, `image`, `audio`, `video`,
  /// `youtube`, `text` or `other`.
  final String kind;
  final String label;
  final String? detail;

  String get kindLabel => switch (kind) {
    'note' => 'Note',
    'file' => 'File',
    'pdf' => 'PDF',
    'image' => 'Image',
    'audio' => 'Audio',
    'video' => 'Video',
    'youtube' => 'YouTube',
    'text' => 'Text',
    _ => 'Source',
  };

  IconData get icon => switch (kind) {
    'note' => Icons.description_outlined,
    'file' => Icons.attach_file,
    'pdf' => Icons.picture_as_pdf_outlined,
    'image' => Icons.image_outlined,
    'audio' => Icons.audiotrack_outlined,
    'video' => Icons.movie_outlined,
    'youtube' => Icons.smart_display_outlined,
    'text' => Icons.notes_outlined,
    _ => Icons.source_outlined,
  };

  @override
  bool operator ==(Object other) =>
      other is SourceSummaryEntry &&
      other.kind == kind &&
      other.label == label &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(kind, label, detail);

  @override
  String toString() => 'SourceSummaryEntry($kind, $label, $detail)';
}

/// Fields of [QuizSource] the detail screen renders on its own.
const _knownKeys = {
  'context_text',
  'contextText',
  'youtube_url',
  'youtubeUrl',
  'provider',
  'model',
};

/// The sources summary of [source], whatever shape it has. `QuizSource` may
/// carry extra fields describing the notes / files / videos used for
/// generation; they are read from its JSON so this works with any field
/// names (lists of strings or of maps with `kind`/`type` + `label`/`title`/
/// `name`/`url`).
List<SourceSummaryEntry> sourceSummaryOf(QuizSource source) {
  try {
    final json = jsonDecode(jsonEncode(source.toJson()));
    return json is Map<String, dynamic> ? sourceSummaryFromJson(json) : [];
  } on Object {
    return const [];
  }
}

/// See [sourceSummaryOf]; takes the source's JSON map.
List<SourceSummaryEntry> sourceSummaryFromJson(Map<String, dynamic> json) {
  final out = <SourceSummaryEntry>[];
  void add(SourceSummaryEntry? e) {
    if (e != null && !out.contains(e)) out.add(e);
  }

  for (final MapEntry(:key, :value) in json.entries) {
    if (_knownKeys.contains(key) || value == null) continue;
    final keyKind = _kindFromKey(key);
    if (value is List) {
      for (final item in value) {
        add(_entry(item, keyKind));
      }
    } else if (value is Map) {
      // Either one source, or a map of lists (e.g. {notes: [...], files: []}).
      final nested = value.cast<String, dynamic>();
      if (nested.values.any((v) => v is List)) {
        for (final e in sourceSummaryFromJson(nested)) {
          add(e);
        }
      } else {
        add(_entry(nested, keyKind));
      }
    } else if (value is String && keyKind != null) {
      add(_entry(value, keyKind));
    }
  }
  return out;
}

SourceSummaryEntry? _entry(Object? item, String? keyKind) {
  if (item is String) {
    final label = item.trim();
    if (label.isEmpty) return null;
    return SourceSummaryEntry(kind: keyKind ?? 'other', label: label);
  }
  if (item is! Map) return null;
  final m = item.cast<String, dynamic>();
  String? str(List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  final rawKind = str(['kind', 'type', 'source_type', 'sourceType']);
  final mime = str(['mime_type', 'mimeType', 'mime']);
  final label = str([
    'label',
    'title',
    'name',
    'file_name',
    'fileName',
    'note_title',
    'noteTitle',
    'url',
  ]);
  if (label == null) return null;
  final kind = _normalizeKind(rawKind, mime) ?? keyKind ?? 'other';
  final detail = str(['detail', 'description']);
  return SourceSummaryEntry(kind: kind, label: label, detail: detail);
}

String? _kindFromKey(String key) {
  final k = key.toLowerCase();
  if (k.contains('note')) return 'note';
  if (k.contains('youtube') || k.contains('video_url')) return 'youtube';
  if (k.contains('file') || k.contains('attachment')) return 'file';
  return null;
}

String? _normalizeKind(String? raw, String? mime) {
  final k = raw?.toLowerCase();
  if (k != null) {
    if (k.contains('youtube')) return 'youtube';
    if (k.contains('note')) return 'note';
    if (k.contains('pdf')) return 'pdf';
    if (k.contains('image')) return 'image';
    if (k.contains('audio')) return 'audio';
    if (k.contains('video')) return 'video';
    if (k.contains('text')) return 'text';
    if (k.contains('file') || k.contains('attachment')) return _fromMime(mime);
  }
  return mime == null ? null : _fromMime(mime);
}

String _fromMime(String? mime) {
  final m = mime?.toLowerCase() ?? '';
  if (m == 'application/pdf') return 'pdf';
  if (m.startsWith('image/')) return 'image';
  if (m.startsWith('audio/')) return 'audio';
  if (m.startsWith('video/')) return 'video';
  return 'file';
}
