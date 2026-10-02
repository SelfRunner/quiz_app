import 'package:flutter/services.dart';

/// Pure Markdown editing helpers operating on [TextEditingValue] (used by the
/// editor toolbar; unit-testable without widgets).
abstract final class MarkdownEditing {
  /// Wraps the selection in [before]/[after] (e.g. `**`). With an empty
  /// selection inserts `before + placeholder + after` and selects the
  /// placeholder. If the selection is already wrapped, unwraps it.
  static TextEditingValue wrap(
    TextEditingValue value,
    String before,
    String after, {
    String placeholder = 'text',
  }) {
    final sel = _normalized(value);
    final text = value.text;
    final selected = sel.textInside(text);

    // Toggle off when the markers surround the selection.
    if (selected.isNotEmpty &&
        sel.start >= before.length &&
        sel.end + after.length <= text.length &&
        text.substring(sel.start - before.length, sel.start) == before &&
        text.substring(sel.end, sel.end + after.length) == after) {
      final newText = text.replaceRange(
        sel.start - before.length,
        sel.end + after.length,
        selected,
      );
      return TextEditingValue(
        text: newText,
        selection: TextSelection(
          baseOffset: sel.start - before.length,
          extentOffset: sel.end - before.length,
        ),
      );
    }

    final inner = selected.isEmpty ? placeholder : selected;
    final newText = text.replaceRange(
      sel.start,
      sel.end,
      '$before$inner$after',
    );
    final innerStart = sel.start + before.length;
    return TextEditingValue(
      text: newText,
      selection: TextSelection(
        baseOffset: innerStart,
        extentOffset: innerStart + inner.length,
      ),
    );
  }

  /// Adds [prefix] (e.g. `# `, `- `) to every line touched by the selection.
  /// When every line already has it, removes it instead. [numbered] uses
  /// `1. `, `2. `, ... prefixes.
  static TextEditingValue prefixLines(
    TextEditingValue value,
    String prefix, {
    bool numbered = false,
  }) {
    final sel = _normalized(value);
    final text = value.text;
    final lineStart = sel.start == 0
        ? 0
        : text.lastIndexOf('\n', sel.start - 1) + 1;
    var lineEnd = text.indexOf('\n', sel.end);
    if (lineEnd == -1) lineEnd = text.length;
    final lines = text.substring(lineStart, lineEnd).split('\n');

    final numberedPrefix = RegExp(r'^\d+\. ');
    bool has(String line) =>
        numbered ? numberedPrefix.hasMatch(line) : line.startsWith(prefix);
    final remove = lines.every(has);

    final out = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (remove) {
        out.add(
          numbered
              ? line.replaceFirst(numberedPrefix, '')
              : line.substring(prefix.length),
        );
      } else {
        // Replace an existing heading level instead of stacking (# # x).
        var base = line;
        if (prefix.startsWith('#')) {
          base = base.replaceFirst(RegExp(r'^#{1,6} '), '');
        }
        out.add('${numbered ? '${i + 1}. ' : prefix}$base');
      }
    }
    final replacement = out.join('\n');
    final newText = text.replaceRange(lineStart, lineEnd, replacement);
    final collapsed = sel.isCollapsed;
    final cursor = lineStart + replacement.length;
    return TextEditingValue(
      text: newText,
      selection: collapsed
          ? TextSelection.collapsed(offset: cursor)
          : TextSelection(baseOffset: lineStart, extentOffset: cursor),
    );
  }

  /// Inserts [block] on its own line(s) at the cursor (replacing any
  /// selection) and places the cursor after it.
  static TextEditingValue insertBlock(TextEditingValue value, String block) {
    final sel = _normalized(value);
    final text = value.text;
    final before = text.substring(0, sel.start);
    final after = text.substring(sel.end);
    final lead = before.isEmpty || before.endsWith('\n') ? '' : '\n';
    final trail = after.startsWith('\n') ? '' : '\n';
    final inserted = '$lead$block$trail';
    final cursor = before.length + inserted.length;
    return TextEditingValue(
      text: '$before$inserted$after',
      selection: TextSelection.collapsed(offset: cursor),
    );
  }

  /// Fenced code block around the selection (or a placeholder).
  static TextEditingValue codeBlock(TextEditingValue value) {
    final sel = _normalized(value);
    final selected = sel.textInside(value.text);
    final body = selected.isEmpty ? 'code' : selected;
    final inserted = insertBlock(value, '```\n$body\n```');
    if (selected.isNotEmpty) return inserted;
    // Select the placeholder.
    final start = inserted.text.indexOf('```\ncode\n```', sel.start) + 4;
    return inserted.copyWith(
      selection: TextSelection(baseOffset: start, extentOffset: start + 4),
    );
  }

  /// `[label](url)`; label defaults to the selection, else the URL.
  static TextEditingValue link(
    TextEditingValue value, {
    required String url,
    String? label,
  }) {
    final sel = _normalized(value);
    final selected = sel.textInside(value.text);
    final text = (label?.isNotEmpty ?? false)
        ? label!
        : (selected.isNotEmpty ? selected : url);
    final md = '[$text]($url)';
    final newText = value.text.replaceRange(sel.start, sel.end, md);
    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: sel.start + md.length),
    );
  }

  /// `![alt](url)` on its own line.
  static TextEditingValue image(
    TextEditingValue value, {
    required String url,
    String alt = 'image',
  }) => insertBlock(value, '![$alt]($url)');

  /// Selection clamped to the text; an invalid selection means "at the end".
  static TextSelection _normalized(TextEditingValue value) {
    final len = value.text.length;
    final s = value.selection;
    if (!s.isValid) return TextSelection.collapsed(offset: len);
    final start = s.start.clamp(0, len);
    final end = s.end.clamp(0, len);
    return TextSelection(baseOffset: start, extentOffset: end);
  }
}

/// Short plain-text preview of Markdown (for list tiles).
String markdownPreviewText(String markdown, {int maxLength = 160}) {
  var s = markdown
      .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
      .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), ' ')
      .replaceAllMapped(
        RegExp(r'\[([^\]]*)\]\([^)]*\)'),
        (m) => m.group(1) ?? '',
      )
      .replaceAll(
        RegExp(r'^\s{0,3}(#{1,6}|>|[-*+]|\d+\.)\s+', multiLine: true),
        '',
      )
      .replaceAll(RegExp(r'[*_`~]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (s.length > maxLength) s = '${s.substring(0, maxLength).trimRight()}…';
  return s;
}
