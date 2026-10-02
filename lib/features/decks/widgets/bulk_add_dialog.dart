import 'package:flutter/material.dart';

import '../../../core/widgets/design_system.dart';
import '../domain/bulk_cards.dart';
import '../domain/deck_format.dart';

/// Asks for many cards at once, one per line (`front :: back`), and returns
/// the parsed cards (null when cancelled).
Future<List<CardText>?> showBulkAddDialog(BuildContext context) =>
    showDialog<List<CardText>>(
      context: context,
      builder: (_) => const _BulkAddDialog(),
    );

class _BulkAddDialog extends StatefulWidget {
  const _BulkAddDialog();

  @override
  State<_BulkAddDialog> createState() => _BulkAddDialogState();
}

class _BulkAddDialogState extends State<_BulkAddDialog> {
  final _text = TextEditingController();
  BulkParseResult _result = const BulkParseResult();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final n = _result.cards.length;
    final bad = _result.invalidLines;
    return AlertDialog(
      title: const Text('Add cards in bulk'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'One card per line: front :: back (optionally :: hint). '
              'Tab-separated lines work too.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.mutedText,
              ),
            ),
            Gaps.h12,
            TextField(
              key: const Key('bulk-text'),
              controller: _text,
              autofocus: true,
              minLines: 8,
              maxLines: 16,
              keyboardType: TextInputType.multiline,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
              ),
              decoration: const InputDecoration(
                hintText:
                    'Mitochondria :: Powerhouse of the cell\n'
                    'H2O :: Water :: Two hydrogens, one oxygen',
              ),
              onChanged: (v) => setState(() => _result = parseBulkCards(v)),
            ),
            Gaps.h8,
            Text(
              [
                plural(n, 'card'),
                if (bad.isNotEmpty)
                  '${bad.length == 1 ? 'line' : 'lines'} '
                      '${bad.take(8).join(', ')}${bad.length > 8 ? '…' : ''} '
                      'skipped (need front :: back)',
              ].join(' · '),
              key: const Key('bulk-summary'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: bad.isEmpty ? colors.mutedText : colors.warning,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('bulk-add'),
          onPressed: n == 0
              ? null
              : () => Navigator.of(context).pop(_result.cards),
          child: Text(n == 0 ? 'Add cards' : 'Add ${plural(n, 'card')}'),
        ),
      ],
    );
  }
}
