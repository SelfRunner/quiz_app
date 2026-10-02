import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_colors.dart';
import '../utils/file_saver.dart';
import 'error_message.dart';

/// A built export file: name (with extension) and bytes.
typedef ExportFile = (String fileName, Uint8List bytes);

/// One export format offered by an [ExportMenu], e.g.
/// `ExportItem(label: 'CSV', build: () async => ('deck.csv', bytes))`.
@immutable
class ExportItem {
  const ExportItem({
    required this.label,
    required this.build,
    this.icon,
    this.key,
  });

  /// Menu label, e.g. "Markdown (.zip)".
  final String label;
  final IconData? icon;

  /// Builds the file (called when the item is chosen).
  final Future<ExportFile> Function() build;

  /// Key of the menu entry (tests).
  final Key? key;
}

/// Builds [item] and hands it to [fileSaverProvider]; shows a progress
/// snackbar for slow builds and a result / error snackbar. Returns true
/// when saved. Usable from any menu (e.g. a subject's "More" menu).
Future<bool> runExport(
  BuildContext context,
  WidgetRef ref,
  ExportItem item,
) async {
  final saver = ref.read(fileSaverProvider);
  try {
    final (name, bytes) = await item.build();
    final path = await saver.save(name, bytes, mimeType: mimeTypeFor(name));
    if (context.mounted) {
      showAppSnackBar(
        context,
        path == null ? 'Exported "$name"' : 'Saved to $path',
      );
    }
    return true;
  } catch (e) {
    if (context.mounted) showErrorSnackBar(context, e, prefix: 'Export failed');
    return false;
  }
}

/// "Export" icon button with a menu of formats ([items]); choosing one
/// builds the file and saves / downloads it via [runExport]. With a single
/// item the button exports directly (tooltip "Export <label>").
class ExportMenu extends ConsumerWidget {
  const ExportMenu({
    super.key,
    required this.items,
    this.tooltip = 'Export',
    this.icon = Icons.file_download_outlined,
  });

  final List<ExportItem> items;
  final String tooltip;
  final IconData icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.length == 1) {
      final item = items.single;
      return IconButton(
        key: item.key,
        tooltip: '$tooltip ${item.label}',
        icon: Icon(icon),
        onPressed: () => runExport(context, ref, item),
      );
    }
    return PopupMenuButton<int>(
      tooltip: tooltip,
      icon: Icon(icon),
      onSelected: (i) => runExport(context, ref, items[i]),
      itemBuilder: (context) => [
        for (final (i, item) in items.indexed)
          PopupMenuItem(
            key: item.key,
            value: i,
            child: ListTile(
              leading: Icon(
                item.icon ?? Icons.description_outlined,
                color: AppColors.of(context).mutedText,
              ),
              title: Text(item.label),
              contentPadding: EdgeInsets.zero,
            ),
          ),
      ],
    );
  }
}
