import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown/markdown.dart' as md;

import '../../data/data_providers.dart';
import '../../data/models/note_image_ref.dart';
import 'error_message.dart';

/// Image bytes for a `note-image://` reference (local cache, else download).
/// Null when unavailable (e.g. offline and not cached).
final noteImageBytesProvider = FutureProvider.autoDispose
    .family<Uint8List?, NoteImageRef>(
      (ref, image) => ref.watch(imageStoreProvider).load(image),
    );

/// Renders note Markdown (GitHub flavored) and resolves
/// `![alt](note-image://owner/note/file)` images through `ImageStore`.
/// Tapping a link copies it to the clipboard.
class NoteMarkdown extends StatelessWidget {
  const NoteMarkdown({
    super.key,
    required this.data,
    this.selectable = true,
    this.shrinkWrap = true,
    this.padding = EdgeInsets.zero,
  });

  final String data;
  final bool selectable;

  /// True: a non-scrolling [MarkdownBody] (embed in a scroll view).
  /// False: a scrolling [Markdown] list.
  final bool shrinkWrap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final styleSheet = MarkdownStyleSheet.fromTheme(theme).copyWith(
      code: theme.textTheme.bodyMedium?.copyWith(
        fontFamily: 'monospace',
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
      ),
      codeblockDecoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      blockquoteDecoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          left: BorderSide(color: theme.colorScheme.primary, width: 4),
        ),
      ),
    );
    void onTapLink(String text, String? href, String title) {
      if (href == null || href.isEmpty) return;
      Clipboard.setData(ClipboardData(text: href)).ignore();
      showAppSnackBar(context, 'Link copied: $href');
    }

    Widget imageBuilder(Uri uri, String? title, String? alt) =>
        NoteMarkdownImage(uri: uri, alt: alt);

    final extensionSet = md.ExtensionSet.gitHubFlavored;
    if (shrinkWrap) {
      return Padding(
        padding: padding,
        child: MarkdownBody(
          data: data,
          selectable: selectable,
          styleSheet: styleSheet,
          extensionSet: extensionSet,
          imageBuilder: imageBuilder,
          onTapLink: onTapLink,
        ),
      );
    }
    return Markdown(
      data: data,
      selectable: selectable,
      styleSheet: styleSheet,
      extensionSet: extensionSet,
      imageBuilder: imageBuilder,
      onTapLink: onTapLink,
      padding: padding,
    );
  }
}

/// One Markdown image: `note-image://` via `ImageStore`, http(s) via network.
class NoteMarkdownImage extends ConsumerWidget {
  const NoteMarkdownImage({super.key, required this.uri, this.alt});

  final Uri uri;
  final String? alt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = uri.scheme == NoteImageRef.scheme
        ? NoteImageRef.tryParse(uri.toString())
        : null;
    if (image != null) {
      final bytes = ref.watch(noteImageBytesProvider(image));
      return bytes.when(
        data: (data) => data == null
            ? _Unavailable(alt: alt, offline: true)
            : _Framed(
                child: Image.memory(
                  data,
                  semanticLabel: alt,
                  errorBuilder: (_, _, _) => _Unavailable(alt: alt),
                ),
              ),
        error: (_, _) => _Unavailable(alt: alt),
        loading: () => const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      return _Framed(
        child: Image.network(
          uri.toString(),
          semanticLabel: alt,
          errorBuilder: (_, _, _) => _Unavailable(alt: alt),
        ),
      );
    }
    return _Unavailable(alt: alt);
  }
}

class _Framed extends StatelessWidget {
  const _Framed({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: 480),
    child: ClipRRect(borderRadius: BorderRadius.circular(8), child: child),
  );
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({this.alt, this.offline = false});

  final String? alt;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = [
      if (alt != null && alt!.isNotEmpty) alt!,
      offline ? 'Image unavailable offline' : 'Image unavailable',
    ].join(' - ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
