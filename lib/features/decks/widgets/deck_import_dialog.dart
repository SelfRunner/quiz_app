import 'package:flutter/material.dart';

import '../../../core/widgets/design_system.dart';
import '../../../data/models/deck.dart';
import '../../../io/import_report.dart';
import '../domain/deck_format.dart';

/// Preview of a CSV / Anki TSV import before anything is saved: how many
/// cards are ready, every skipped row with its line number, warnings and
/// the first cards. Returns true when the user confirms.
Future<bool> showDeckImportPreview(
  BuildContext context, {
  required String fileName,
  required ImportResult<Flashcard> result,
  String? target,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => DeckImportPreviewDialog(
        fileName: fileName,
        result: result,
        target: target,
      ),
    ) ??
    false;

class DeckImportPreviewDialog extends StatelessWidget {
  const DeckImportPreviewDialog({
    super.key,
    required this.fileName,
    required this.result,
    this.target,
  });

  final String fileName;
  final ImportResult<Flashcard> result;

  /// Deck title the cards are added to (null = a new deck).
  final String? target;

  static const int previewCount = 5;
  static const Key confirmKey = Key('deck-import-confirm');

  /// `Line 4: Missing back.`
  static String issueText(ImportIssue issue) {
    final where = [
      if (issue.line != null) 'Line ${issue.line}',
      ?issue.field,
    ].join(', ');
    return where.isEmpty ? issue.message : '$where: ${issue.message}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final cards = result.items;
    final n = cards.length;
    final skipped = result.errors.length;
    final muted = theme.textTheme.bodySmall?.copyWith(color: colors.mutedText);

    Widget issues(List<ImportIssue> list, Color color, Key key) => Container(
      key: key,
      constraints: const BoxConstraints(maxHeight: 140),
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.md,
        vertical: Insets.sm,
      ),
      decoration: BoxDecoration(
        borderRadius: Radii.mdAll,
        border: Border.all(color: colors.hairline),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final issue in list)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Insets.xxs),
                child: Text(
                  issueText(issue),
                  style: theme.textTheme.bodySmall?.copyWith(color: color),
                ),
              ),
          ],
        ),
      ),
    );

    return AlertDialog(
      title: Text(target == null ? 'Import deck' : 'Import cards'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                target == null ? fileName : '$fileName → "$target"',
                style: muted,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Gaps.h8,
              Text(
                [
                  '${plural(n, 'card')} ready',
                  if (skipped > 0) '${plural(skipped, 'row')} skipped',
                ].join(' · '),
                key: const Key('deck-import-summary'),
                style: theme.textTheme.titleSmall,
              ),
              if (result.errors.isNotEmpty) ...[
                Gaps.h12,
                Text('Skipped rows', style: theme.textTheme.labelLarge),
                Gaps.h4,
                issues(
                  result.errors,
                  colors.danger,
                  const Key('deck-import-errors'),
                ),
              ],
              if (result.warnings.isNotEmpty) ...[
                Gaps.h12,
                Text('Warnings', style: theme.textTheme.labelLarge),
                Gaps.h4,
                issues(
                  result.warnings,
                  colors.warning,
                  const Key('deck-import-warnings'),
                ),
              ],
              if (n > 0) ...[
                Gaps.h12,
                Text('Preview', style: theme.textTheme.labelLarge),
                Gaps.h4,
                for (final c in cards.take(previewCount))
                  ListRowTile(
                    dense: true,
                    padding: const EdgeInsets.symmetric(vertical: Insets.xs),
                    title: Text(c.front),
                    subtitle: Text(c.back),
                  ),
                if (n > previewCount)
                  Text(
                    '+ ${plural(n - previewCount, 'more card')}',
                    style: muted,
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: confirmKey,
          onPressed: n == 0 ? null : () => Navigator.of(context).pop(true),
          child: Text(n == 0 ? 'Import' : 'Import ${plural(n, 'card')}'),
        ),
      ],
    );
  }
}
