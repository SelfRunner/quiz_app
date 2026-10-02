import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/c.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/csharp.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/diff.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/latex.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/php.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/r.dart';
import 'package:re_highlight/languages/ruby.dart';
import 'package:re_highlight/languages/rust.dart';
import 'package:re_highlight/languages/sql.dart';
import 'package:re_highlight/languages/swift.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart';

import '../../../../core/widgets/design_system.dart';
import '../../../../core/widgets/error_message.dart';

/// Languages offered by the editor's code-block menu (fence tag -> label).
const Map<String, String> kCodeLanguages = {
  'python': 'Python',
  'javascript': 'JavaScript',
  'typescript': 'TypeScript',
  'java': 'Java',
  'kotlin': 'Kotlin',
  'dart': 'Dart',
  'c': 'C',
  'cpp': 'C++',
  'csharp': 'C#',
  'go': 'Go',
  'rust': 'Rust',
  'swift': 'Swift',
  'sql': 'SQL',
  'bash': 'Shell',
  'json': 'JSON',
  'yaml': 'YAML',
  'html': 'HTML',
  'css': 'CSS',
  'latex': 'LaTeX',
};

/// Syntax highlighting for note code blocks (highlight.js grammars via
/// `re_highlight`; only the languages below are bundled).
abstract final class NoteSyntaxHighlighter {
  static Highlight? _instance;

  static Highlight get _highlight => _instance ??= Highlight()
    ..registerLanguages({
      'bash': langBash,
      'c': langC,
      'cpp': langCpp,
      'csharp': langCsharp,
      'css': langCss,
      'dart': langDart,
      'diff': langDiff,
      'go': langGo,
      'java': langJava,
      'javascript': langJavascript,
      'json': langJson,
      'kotlin': langKotlin,
      'latex': langLatex,
      'markdown': langMarkdown,
      'php': langPhp,
      'python': langPython,
      'r': langR,
      'ruby': langRuby,
      'rust': langRust,
      'sql': langSql,
      'swift': langSwift,
      'typescript': langTypescript,
      'xml': langXml,
      'yaml': langYaml,
    })
    ..registerAliases(['shell', 'zsh', 'console'], 'bash')
    ..registerAliases(['py'], 'python')
    ..registerAliases(['cs', 'c#'], 'csharp')
    ..registerAliases(['kt'], 'kotlin')
    ..registerAliases(['tex'], 'latex')
    ..registerAliases(['md'], 'markdown');

  /// Whether [language] (fence tag or alias) is highlighted.
  static bool supports(String language) =>
      language.isNotEmpty && _highlight.getLanguage(language) != null;

  /// Highlighted spans for [code], or null for unknown languages / errors.
  static TextSpan? highlight(
    String code,
    String language, {
    required TextStyle base,
    required Map<String, TextStyle> theme,
  }) {
    if (!supports(language)) return null;
    try {
      final result = _highlight.highlight(code: code, language: language);
      final renderer = TextSpanRenderer(base, theme);
      result.render(renderer);
      return renderer.span;
    } catch (_) {
      return null;
    }
  }

  /// A quiet palette that fits the app's neutral surfaces.
  static Map<String, TextStyle> theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final keyword = TextStyle(
      color: dark ? const Color(0xFFC4A5F5) : const Color(0xFF7C3AED),
    );
    final string = TextStyle(
      color: dark ? const Color(0xFF9AD8A6) : const Color(0xFF15803D),
    );
    final number = TextStyle(
      color: dark ? const Color(0xFFF2B37E) : const Color(0xFFB45309),
    );
    final title = TextStyle(
      color: dark ? const Color(0xFF8DB4F7) : const Color(0xFF2556C8),
    );
    final type = TextStyle(
      color: dark ? const Color(0xFF7FD3D0) : const Color(0xFF0F766E),
    );
    final comment = TextStyle(
      color: dark ? const Color(0xFF8A8784) : const Color(0xFF8C8985),
      fontStyle: FontStyle.italic,
    );
    final danger = TextStyle(
      color: dark ? const Color(0xFFF59C9C) : const Color(0xFFB42318),
    );
    return {
      'keyword': keyword,
      'selector-tag': keyword,
      'doctag': keyword,
      'meta keyword': keyword,
      'built_in': type,
      'type': type,
      'class': type,
      'title.class': type,
      'title.class_': type,
      'title.class_.inherited__': type,
      'literal': number,
      'number': number,
      'symbol': number,
      'variable.constant': number,
      'string': string,
      'regexp': string,
      'char.escape': string,
      'meta-string': string,
      'meta string': string,
      'addition': string,
      'title': title,
      'title.function': title,
      'title.function_': title,
      'function': title,
      'section': title.copyWith(fontWeight: FontWeight.w600),
      'name': title,
      'tag': title,
      'attr': number,
      'attribute': number,
      'property': title,
      'selector-class': number,
      'selector-id': number,
      'variable': danger,
      'template-variable': danger,
      'variable.language': keyword,
      'deletion': danger,
      'subst': const TextStyle(),
      'comment': comment,
      'quote': comment,
      'meta': comment.copyWith(fontStyle: FontStyle.normal),
      'emphasis': const TextStyle(fontStyle: FontStyle.italic),
      'strong': const TextStyle(fontWeight: FontWeight.w700),
      'link': title.copyWith(decoration: TextDecoration.underline),
      'bullet': number,
    };
  }
}

/// A fenced code block: language label, copy button, highlighted code that
/// scrolls horizontally.
class NoteCodeBlock extends StatefulWidget {
  const NoteCodeBlock({super.key, required this.code, this.language = ''});

  final String code;
  final String language;

  @override
  State<NoteCodeBlock> createState() => _NoteCodeBlockState();
}

class _NoteCodeBlockState extends State<NoteCodeBlock> {
  final _scroll = ScrollController();
  bool _copied = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    showAppSnackBar(context, 'Code copied');
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final base = theme.textTheme.bodyMedium!.copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
      fontSize: 13.5,
      height: 1.5,
      color: theme.colorScheme.onSurface,
    );
    final span =
        NoteSyntaxHighlighter.highlight(
          widget.code,
          widget.language,
          base: base,
          theme: NoteSyntaxHighlighter.theme(theme.brightness),
        ) ??
        TextSpan(text: widget.code, style: base);
    final language = widget.language.isEmpty
        ? 'Code'
        : (kCodeLanguages[widget.language.toLowerCase()] ?? widget.language);

    return Container(
      key: const Key('note-code-block'),
      decoration: BoxDecoration(
        color: colors.sidebar,
        borderRadius: Radii.mdAll,
        border: Border.all(color: colors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Insets.md,
              Insets.xs,
              Insets.xs,
              0,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    language,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.mutedText,
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('note-code-copy'),
                  tooltip: _copied ? 'Copied' : 'Copy code',
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  color: colors.mutedText,
                  icon: Icon(_copied ? Icons.check : Icons.content_copy),
                  onPressed: _copy,
                ),
              ],
            ),
          ),
          Scrollbar(
            controller: _scroll,
            child: SingleChildScrollView(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(
                Insets.md,
                0,
                Insets.md,
                Insets.md,
              ),
              child: Text.rich(span, softWrap: false),
            ),
          ),
        ],
      ),
    );
  }
}
