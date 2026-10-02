import 'package:flutter/material.dart';

import '../../../core/utils/clock.dart';
import '../../../core/widgets/design_system.dart';
import '../../../data/models/deck.dart';
import '../domain/deck_format.dart';
import 'bulk_add_dialog.dart';

/// Reorderable list of flashcards edited in place (front, back, optional
/// hint), with add / bulk add / duplicate / delete (undo). Used by the deck
/// editor and the AI deck preview.
///
/// Controlled: [cards] is the source of truth and every edit calls
/// [onChanged] with a new list. It is a scrollable ([ReorderableListView]);
/// put the rest of the form in [header].
class DeckCardListEditor extends StatefulWidget {
  const DeckCardListEditor({
    super.key,
    required this.cards,
    required this.onChanged,
    required this.newId,
    this.header,
    this.showIssues = false,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 96),
  });

  final List<Flashcard> cards;
  final ValueChanged<List<Flashcard>> onChanged;
  final IdGenerator newId;
  final Widget? header;

  /// Highlight cards with an empty side (e.g. after a failed save).
  final bool showIssues;
  final EdgeInsets padding;

  @override
  State<DeckCardListEditor> createState() => _DeckCardListEditorState();
}

class _Fields {
  _Fields(Flashcard c)
    : front = TextEditingController(text: c.front),
      back = TextEditingController(text: c.back),
      hint = TextEditingController(text: c.hint ?? '');

  final TextEditingController front;
  final TextEditingController back;
  final TextEditingController hint;

  void sync(Flashcard c) {
    void set(TextEditingController t, String v) {
      if (t.text != v) t.text = v;
    }

    set(front, c.front);
    set(back, c.back);
    set(hint, c.hint ?? '');
  }

  void dispose() {
    front.dispose();
    back.dispose();
    hint.dispose();
  }
}

class _DeckCardListEditorState extends State<DeckCardListEditor> {
  final Map<String, _Fields> _fields = {};
  String? _autofocusId;

  _Fields _fieldsFor(Flashcard c) =>
      _fields.putIfAbsent(c.id, () => _Fields(c));

  @override
  void didUpdateWidget(DeckCardListEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (final c in widget.cards) {
      _fields[c.id]?.sync(c);
    }
  }

  @override
  void dispose() {
    for (final f in _fields.values) {
      f.dispose();
    }
    super.dispose();
  }

  List<Flashcard> get _cards => widget.cards;

  void _replace(String id, Flashcard Function(Flashcard c) change) {
    final i = _cards.indexWhere((c) => c.id == id);
    if (i < 0) return;
    widget.onChanged([..._cards]..[i] = change(_cards[i]));
  }

  void _add() {
    final card = Flashcard(id: widget.newId(), front: '', back: '');
    setState(() => _autofocusId = card.id);
    widget.onChanged([..._cards, card]);
  }

  Future<void> _bulkAdd() async {
    final parsed = await showBulkAddDialog(context);
    if (parsed == null || parsed.isEmpty || !mounted) return;
    // Replace a single trailing blank card instead of leaving it behind.
    final base = [..._cards];
    if (base.isNotEmpty && isBlankCard(base.last)) base.removeLast();
    widget.onChanged([
      ...base,
      for (final p in parsed)
        Flashcard(
          id: widget.newId(),
          front: p.front,
          back: p.back,
          hint: p.hint,
        ),
    ]);
    showSnack(context, 'Added ${plural(parsed.length, 'card')}');
  }

  void _duplicate(int index) {
    final copy = _cards[index].copyWith(id: widget.newId());
    widget.onChanged([..._cards]..insert(index + 1, copy));
  }

  void _delete(int index) {
    final before = [..._cards];
    final removed = _cards[index];
    widget.onChanged([..._cards]..removeAt(index));
    if (isBlankCard(removed)) return;
    final front = removed.front.trim().replaceAll(RegExp(r'\s+'), ' ');
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Deleted "${front.length > 40 ? '${front.substring(0, 39)}…' : front}"',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => widget.onChanged(before),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final autofocus = _autofocusId;
    _autofocusId = null;
    return ReorderableListView.builder(
      padding: widget.padding,
      buildDefaultDragHandles: false,
      header: widget.header,
      footer: Padding(
        padding: const EdgeInsets.only(top: Insets.xs),
        child: Wrap(
          spacing: Insets.sm,
          children: [
            TextButton.icon(
              key: const Key('add-card'),
              onPressed: _add,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add card'),
            ),
            TextButton.icon(
              key: const Key('bulk-add-cards'),
              onPressed: _bulkAdd,
              icon: const Icon(Icons.playlist_add, size: 18),
              label: const Text('Bulk add'),
            ),
          ],
        ),
      ),
      itemCount: _cards.length,
      onReorderItem: (oldIndex, newIndex) {
        final list = [..._cards];
        final item = list.removeAt(oldIndex);
        list.insert(newIndex, item);
        widget.onChanged(list);
      },
      itemBuilder: (context, index) {
        final card = _cards[index];
        return Padding(
          key: ValueKey(card.id),
          padding: const EdgeInsets.only(bottom: Insets.sm),
          child: _CardEditorTile(
            index: index,
            card: card,
            fields: _fieldsFor(card),
            autofocus: card.id == autofocus,
            issues: widget.showIssues && !isBlankCard(card)
                ? cardIssues(card)
                : const [],
            onChanged: (change) => _replace(card.id, change),
            onDuplicate: () => _duplicate(index),
            onDelete: () => _delete(index),
          ),
        );
      },
    );
  }
}

enum _TileAction { duplicate, delete }

class _CardEditorTile extends StatelessWidget {
  const _CardEditorTile({
    required this.index,
    required this.card,
    required this.fields,
    required this.autofocus,
    required this.issues,
    required this.onChanged,
    required this.onDuplicate,
    required this.onDelete,
  });

  final int index;
  final Flashcard card;
  final _Fields fields;
  final bool autofocus;
  final List<String> issues;
  final void Function(Flashcard Function(Flashcard c) change) onChanged;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final hasIssues = issues.isNotEmpty;
    final showHint = card.hint != null;

    Widget side(
      String label,
      TextEditingController controller,
      void Function(String v) set, {
      Key? key,
      bool focus = false,
    }) => TextField(
      key: key,
      controller: controller,
      autofocus: focus,
      minLines: 1,
      maxLines: 6,
      keyboardType: TextInputType.multiline,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(labelText: label, isDense: true),
      onChanged: set,
    );

    final front = side(
      'Front',
      fields.front,
      (v) => onChanged((c) => c.copyWith(front: v)),
      key: ValueKey('card-front-${card.id}'),
      focus: autofocus,
    );
    final back = side(
      'Back',
      fields.back,
      (v) => onChanged((c) => c.copyWith(back: v)),
      key: ValueKey('card-back-${card.id}'),
    );

    return Material(
      color: colors.card,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.lgAll,
        side: BorderSide(
          color: hasIssues ? colors.danger : colors.hairline,
          width: hasIssues ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Insets.xs,
          Insets.xs,
          Insets.xs,
          Insets.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.all(Insets.xs),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.grab,
                      child: Icon(
                        Icons.drag_indicator,
                        size: 18,
                        color: colors.faintText,
                      ),
                    ),
                  ),
                ),
                Gaps.w4,
                Text(
                  '${index + 1}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.mutedText,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const Spacer(),
                IconButton(
                  key: ValueKey('card-hint-toggle-${card.id}'),
                  tooltip: showHint ? 'Remove hint' : 'Add hint',
                  isSelected: showHint,
                  icon: const Icon(Icons.lightbulb_outline, size: 18),
                  selectedIcon: const Icon(Icons.lightbulb, size: 18),
                  onPressed: () =>
                      onChanged((c) => c.copyWith(hint: showHint ? null : '')),
                ),
                PopupMenuButton<_TileAction>(
                  key: ValueKey('card-menu-${card.id}'),
                  tooltip: 'More actions',
                  icon: const Icon(Icons.more_horiz, size: 18),
                  onSelected: (a) => switch (a) {
                    _TileAction.duplicate => onDuplicate(),
                    _TileAction.delete => onDelete(),
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: _TileAction.duplicate,
                      child: ListTile(
                        leading: Icon(Icons.copy_outlined),
                        title: Text('Duplicate'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _TileAction.delete,
                      child: ListTile(
                        leading: Icon(Icons.delete_outline),
                        title: Text('Delete'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Insets.sm),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 560;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (wide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: front),
                            Gaps.w12,
                            Expanded(child: back),
                          ],
                        )
                      else ...[
                        front,
                        Gaps.h8,
                        back,
                      ],
                      if (showHint) ...[
                        Gaps.h8,
                        TextField(
                          key: ValueKey('card-hint-${card.id}'),
                          controller: fields.hint,
                          minLines: 1,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Hint (optional)',
                            isDense: true,
                          ),
                          onChanged: (v) =>
                              onChanged((c) => c.copyWith(hint: v)),
                        ),
                      ],
                      if (hasIssues) ...[
                        Gaps.h8,
                        for (final m in issues)
                          Row(
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 16,
                                color: colors.danger,
                              ),
                              Gaps.w8,
                              Expanded(
                                child: Text(
                                  m,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.danger,
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
