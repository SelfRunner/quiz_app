import 'package:flutter/services.dart';

/// List kinds for [MarkdownEditing.toggleList].
enum ListKind { bullet, numbered, task, quote }

/// Applies [MarkdownEditing.continueList] when Enter is typed in a list
/// (works with hardware and soft keyboards).
class ListContinuationFormatter extends TextInputFormatter {
  const ListContinuationFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => MarkdownEditing.continueList(oldValue, newValue) ?? newValue;
}

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

  /// Fenced code block (optionally with a [language] tag) around the
  /// selection, or a selected `code` placeholder.
  static TextEditingValue codeBlock(
    TextEditingValue value, {
    String language = '',
  }) => _blockWithPlaceholder(value, '```$language\n', 'code', '\n```');

  /// `$$ ... $$` math block around the selection (or a placeholder formula).
  static TextEditingValue mathBlock(TextEditingValue value) =>
      _blockWithPlaceholder(value, '\$\$\n', 'E = mc^2', '\n\$\$');

  /// Inline math `$...$` around the selection.
  static TextEditingValue mathInline(TextEditingValue value) =>
      wrap(value, r'$', r'$', placeholder: 'x^2');

  /// GitHub alert / callout (`> [!NOTE]`). [type] is one of `NOTE`, `TIP`,
  /// `IMPORTANT`, `WARNING`, `CAUTION`. Quotes the selected lines, else
  /// inserts a selected placeholder.
  static TextEditingValue callout(TextEditingValue value, String type) {
    final sel = _normalized(value);
    final selected = sel.textInside(value.text);
    final header = '> [!${type.toUpperCase()}]\n';
    if (selected.isEmpty) {
      return _blockWithPlaceholder(value, '$header> ', 'Text', '');
    }
    final body = selected.split('\n').map((l) => l.isEmpty ? '>' : '> $l');
    return insertBlock(value, '$header${body.join('\n')}');
  }

  /// A Markdown table with [columns] columns and [rows] body rows; the first
  /// header cell is selected.
  static TextEditingValue table(
    TextEditingValue value, {
    int rows = 2,
    int columns = 3,
  }) {
    final header = [for (var c = 1; c <= columns; c++) 'Column $c'];
    final lines = [
      '| ${header.join(' | ')} |',
      '|${List.filled(columns, ' --- ').join('|')}|',
      for (var r = 0; r < rows; r++)
        '|${List.filled(columns, '   ').join('|')}|',
    ];
    final sel = _normalized(value);
    final inserted = insertBlock(value, lines.join('\n'));
    final start = inserted.text.indexOf('| Column 1', sel.start) + 2;
    return inserted.copyWith(
      selection: TextSelection(baseOffset: start, extentOffset: start + 8),
    );
  }

  /// Inserts `before + (selection or placeholder) + after` as a block and
  /// selects the placeholder when nothing was selected.
  static TextEditingValue _blockWithPlaceholder(
    TextEditingValue value,
    String before,
    String placeholder,
    String after,
  ) {
    final sel = _normalized(value);
    final selected = sel.textInside(value.text);
    final body = selected.isEmpty ? placeholder : selected;
    final block = '$before$body$after';
    final inserted = insertBlock(value, block);
    if (selected.isNotEmpty) return inserted;
    final start = inserted.text.indexOf(block, sel.start) + before.length;
    return inserted.copyWith(
      selection: TextSelection(
        baseOffset: start,
        extentOffset: start + placeholder.length,
      ),
    );
  }

  static final RegExp _listItem = RegExp(
    r'^([ \t]*)(?:([-*+])|(\d{1,9})([.)]))[ \t]+(\[[ xX]\][ \t]+)?',
  );
  static final RegExp _quote = RegExp(r'^[ \t]*(?:>[ \t]?)+');

  /// Toggles a list kind on the selected lines. Existing list markers are
  /// replaced (a bullet becomes a checklist item, ...); when every non-blank
  /// line already is of [kind], the markers are removed. Indentation is kept.
  static TextEditingValue toggleList(TextEditingValue value, ListKind kind) {
    if (kind == ListKind.quote) return prefixLines(value, '> ');
    final sel = _normalized(value);
    final text = value.text;
    final lineStart = sel.start == 0
        ? 0
        : text.lastIndexOf('\n', sel.start - 1) + 1;
    var lineEnd = text.indexOf('\n', sel.end);
    if (lineEnd == -1) lineEnd = text.length;
    final lines = text.substring(lineStart, lineEnd).split('\n');

    ListKind? kindOf(String line) {
      final m = _listItem.firstMatch(line);
      if (m == null) return null;
      if (m.group(5) != null) return ListKind.task;
      return m.group(2) != null ? ListKind.bullet : ListKind.numbered;
    }

    final nonBlank = lines.where((l) => l.trim().isNotEmpty).toList();
    final remove =
        nonBlank.isNotEmpty && nonBlank.every((l) => kindOf(l) == kind);
    var number = 0;
    final out = <String>[];
    for (final line in lines) {
      if (line.trim().isEmpty && lines.length > 1) {
        out.add(line);
        continue;
      }
      final m = _listItem.firstMatch(line);
      final indent = RegExp(r'^[ \t]*').firstMatch(line)!.group(0)!;
      final content = m == null
          ? line.substring(indent.length)
          : line.substring(m.end);
      if (remove) {
        out.add('$indent$content');
        continue;
      }
      final marker = switch (kind) {
        ListKind.bullet => '- ',
        ListKind.numbered => '${++number}. ',
        ListKind.task => '- [ ] ',
        ListKind.quote => '> ',
      };
      out.add('$indent$marker$content');
    }
    final replacement = out.join('\n');
    final newText = text.replaceRange(lineStart, lineEnd, replacement);
    final cursor = lineStart + replacement.length;
    return TextEditingValue(
      text: newText,
      selection: sel.isCollapsed
          ? TextSelection.collapsed(offset: cursor)
          : TextSelection(baseOffset: lineStart, extentOffset: cursor),
    );
  }

  /// Smart list continuation: when [newValue] is [oldValue] plus a newline
  /// typed at the caret inside a list item / quote, continues the list
  /// (`- `, `2. `, `- [ ] `, `> `). Enter on an empty item removes its
  /// marker instead. Returns null when nothing special applies.
  static TextEditingValue? continueList(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final oldSel = oldValue.selection;
    if (!oldSel.isValid || !oldSel.isCollapsed) return null;
    final c = oldSel.baseOffset;
    final text = oldValue.text;
    if (c < 0 || c > text.length) return null;
    if (newValue.text.length != text.length + 1 ||
        newValue.selection.baseOffset != c + 1 ||
        newValue.text != text.replaceRange(c, c, '\n')) {
      return null;
    }
    final lineStart = c == 0 ? 0 : text.lastIndexOf('\n', c - 1) + 1;
    var lineEnd = text.indexOf('\n', c);
    if (lineEnd == -1) lineEnd = text.length;
    final line = text.substring(lineStart, lineEnd);

    String marker;
    int markerLength;
    final item = _listItem.firstMatch(line);
    if (item != null) {
      markerLength = item.end;
      final indent = item.group(1)!;
      final task = item.group(5) != null ? '[ ] ' : '';
      if (item.group(2) != null) {
        marker = '$indent${item.group(2)} $task';
      } else {
        final next = int.parse(item.group(3)!) + 1;
        marker = '$indent$next${item.group(4)} $task';
      }
    } else {
      final quote = _quote.firstMatch(line);
      if (quote == null) return null;
      markerLength = quote.end;
      final q = quote.group(0)!;
      marker = q.endsWith(' ') ? q : '$q ';
    }
    if (c < lineStart + markerLength) return null;

    if (line.substring(markerLength).trim().isEmpty) {
      // Empty item: end the list (clear the marker, no new line).
      return TextEditingValue(
        text: text.replaceRange(lineStart, lineEnd, ''),
        selection: TextSelection.collapsed(offset: lineStart),
      );
    }
    final insert = '\n$marker';
    return TextEditingValue(
      text: text.replaceRange(c, c, insert),
      selection: TextSelection.collapsed(offset: c + insert.length),
    );
  }

  /// Tab / Shift+Tab on list items: nests the selected items under the
  /// previous sibling (indent = that item's marker width) or moves them one
  /// level out. Returns null when the caret line is not a list item.
  static TextEditingValue? indentList(
    TextEditingValue value, {
    bool outdent = false,
  }) {
    final sel = _normalized(value);
    final text = value.text;
    final lineStart = sel.start == 0
        ? 0
        : text.lastIndexOf('\n', sel.start - 1) + 1;
    var lineEnd = text.indexOf('\n', sel.end);
    if (lineEnd == -1) lineEnd = text.length;
    final lines = text.substring(lineStart, lineEnd).split('\n');
    final first = _listItem.firstMatch(lines.first);
    if (first == null) return null;
    final indent = first.group(1)!.length;

    // Previous list items above the selection, nearest first.
    final above = lineStart == 0
        ? <String>[]
        : text.substring(0, lineStart - 1).split('\n').reversed.toList();
    int delta;
    if (outdent) {
      if (indent == 0) return value;
      var target = 0;
      for (final l in above) {
        final m = _listItem.firstMatch(l);
        if (m != null && m.group(1)!.length < indent) {
          target = m.group(1)!.length;
          break;
        }
      }
      delta = target - indent;
    } else {
      delta = first.end - indent - (first.group(5)?.length ?? 0);
      for (final l in above) {
        final m = _listItem.firstMatch(l);
        if (m == null) {
          if (l.trim().isEmpty) continue;
          break;
        }
        final i = m.group(1)!.length;
        if (i == indent) {
          delta = m.end - i - (m.group(5)?.length ?? 0);
          break;
        }
        if (i < indent) break;
      }
    }

    var removedBeforeStart = 0;
    var total = 0;
    final out = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (delta > 0) {
        if (line.trim().isEmpty) {
          out.add(line);
          continue;
        }
        out.add('${' ' * delta}$line');
        total += delta;
        if (i == 0) removedBeforeStart = -delta;
      } else {
        final leading = RegExp(r'^ *').firstMatch(line)!.group(0)!.length;
        final remove = leading < -delta ? leading : -delta;
        out.add(line.substring(remove));
        total -= remove;
        if (i == 0) removedBeforeStart = remove;
      }
    }
    final replacement = out.join('\n');
    final newText = text.replaceRange(lineStart, lineEnd, replacement);
    int clampOffset(int o) =>
        o.clamp(lineStart, lineStart + replacement.length);
    final start = clampOffset(sel.start - removedBeforeStart);
    final end = clampOffset(sel.end + total);
    return TextEditingValue(
      text: newText,
      selection: sel.isCollapsed
          ? TextSelection.collapsed(offset: start)
          : TextSelection(baseOffset: start, extentOffset: end),
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
