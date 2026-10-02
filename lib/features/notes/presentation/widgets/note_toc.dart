import 'package:flutter/material.dart';

import '../../../../core/widgets/design_system.dart';
import '../../application/note_markdown_syntax.dart';

/// Whether a note is long enough to deserve a table of contents.
bool noteNeedsToc(List<NoteHeading> headings) =>
    headings.where((h) => h.level <= 3).length >= 3;

/// "On this page": the note's headings (levels 1-3), indented by level.
class NoteTableOfContents extends StatelessWidget {
  const NoteTableOfContents({
    super.key,
    required this.headings,
    required this.onSelect,
    this.showTitle = true,
  });

  final List<NoteHeading> headings;
  final ValueChanged<NoteHeading> onSelect;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final visible = headings.where((h) => h.level <= 3).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    final minLevel = visible
        .map((h) => h.level)
        .reduce((a, b) => a < b ? a : b);
    return Column(
      key: const Key('note-toc'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showTitle)
          Padding(
            padding: const EdgeInsets.only(bottom: Insets.xs),
            child: Text(
              'On this page',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.mutedText,
              ),
            ),
          ),
        for (final h in visible)
          InkWell(
            key: Key('note-toc-${h.index}'),
            borderRadius: Radii.smAll,
            onTap: () => onSelect(h),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                Insets.sm + (h.level - minLevel) * Insets.md,
                6,
                Insets.sm,
                6,
              ),
              child: Text(
                h.text.isEmpty ? 'Untitled section' : h.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: h.level == minLevel
                      ? theme.colorScheme.onSurface
                      : colors.mutedText,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Table of contents in a bottom sheet (phones). Resolves to the chosen
/// heading.
Future<NoteHeading?> showNoteTocSheet(
  BuildContext context,
  List<NoteHeading> headings,
) => showModalBottomSheet<NoteHeading>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (sheetContext) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.7,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Insets.lg, 0, Insets.lg, Insets.lg),
        child: NoteTableOfContents(
          headings: headings,
          onSelect: (h) => Navigator.of(sheetContext).pop(h),
        ),
      ),
    ),
  ),
);
