import 'note_markdown_syntax.dart';

/// Pure helpers over a note's Markdown source (tasks, word count).
abstract final class NoteDocument {
  static final RegExp _taskLine = RegExp(
    r'^((?:[ \t]*>)*[ \t]*(?:[-+*]|\d{1,9}[.)])[ \t]+)\[([ xX])\](?=[ \t])',
  );
  static final RegExp _fence = RegExp(r'^[ \t]*(?:>[ \t]*)*(`{3,}|~{3,})');
  static final RegExp _mathOpen = RegExp(r'^ {0,3}\$\$(.*)$');

  /// Offsets of the `[` of every task marker (`- [ ] `, `1. [x] `) in
  /// document order, skipping fenced code and `$$` math blocks.
  static List<int> taskOffsets(String markdown) {
    final offsets = <int>[];
    String? fence;
    var inMath = false;
    var offset = 0;
    for (final line in markdown.split('\n')) {
      final lineStart = offset;
      offset += line.length + 1;
      if (inMath) {
        if (line.trimRight().endsWith(r'$$')) inMath = false;
        continue;
      }
      final fenceMatch = _fence.firstMatch(line);
      if (fence != null) {
        final marker = fenceMatch?.group(1);
        if (marker != null &&
            marker[0] == fence[0] &&
            marker.length >= fence.length) {
          fence = null;
        }
        continue;
      }
      if (fenceMatch != null) {
        fence = fenceMatch.group(1);
        continue;
      }
      final math = _mathOpen.firstMatch(line);
      if (math != null) {
        final rest = math.group(1)!.trimRight();
        if (!(rest.length >= 3 && rest.endsWith(r'$$'))) inMath = true;
        continue;
      }
      final task = _taskLine.firstMatch(line);
      if (task != null) offsets.add(lineStart + task.group(1)!.length);
    }
    return offsets;
  }

  /// Sets task [index] (document order) to [checked]. Returns null when the
  /// source cannot be mapped reliably (index out of range, or the scanner and
  /// the Markdown parser disagree on the number of tasks).
  static String? setTask(String markdown, int index, {required bool checked}) {
    final offsets = taskOffsets(markdown);
    if (index < 0 || index >= offsets.length) return null;
    if (parseNoteMarkdown(markdown).taskCount != offsets.length) return null;
    final at = offsets[index];
    return markdown.replaceRange(at, at + 3, checked ? '[x]' : '[ ]');
  }

  /// Number of words, ignoring Markdown syntax (code is counted).
  static int wordCount(String markdown) {
    final text = markdown
        .replaceAll(RegExp(r'^[ \t]*(```|~~~).*$', multiLine: true), ' ')
        .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), ' ')
        .replaceAllMapped(
          RegExp(r'\[([^\]]*)\]\([^)]*\)'),
          (m) => m.group(1) ?? '',
        )
        .replaceAll(RegExp(r'\[![A-Za-z]+\]'), ' ')
        .replaceAll(RegExp(r'\[[ xX]\]'), ' ');
    return RegExp(
      r"[\p{L}\p{N}]+(?:['’\-.][\p{L}\p{N}]+)*",
      unicode: true,
    ).allMatches(text).length;
  }

  /// Estimated reading time in minutes (200 words/min, at least 1 when the
  /// note has any words).
  static int readingMinutes(int words) => words == 0 ? 0 : (words / 200).ceil();

  /// "123 words · 1 min read".
  static String statsLabel(String markdown) {
    final words = wordCount(markdown);
    final minutes = readingMinutes(words);
    final w = words == 1 ? '1 word' : '$words words';
    return minutes == 0 ? w : '$w · $minutes min read';
  }
}
