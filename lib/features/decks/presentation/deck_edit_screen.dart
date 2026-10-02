import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../../core/widgets/design_system.dart';
import '../../../core/widgets/tag_widgets.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/deck.dart';
import '../../../data/models/syncable.dart';
import '../application/deck_io_actions.dart';
import '../domain/deck_format.dart';
import '../widgets/card_list_editor.dart';

enum _LeaveChoice { save, discard }

/// Owner-only deck editor: title, description, tags and the cards (front,
/// back, optional hint) with add / bulk add / import (CSV / Anki TSV) /
/// reorder / duplicate / delete.
class DeckEditScreen extends ConsumerStatefulWidget {
  const DeckEditScreen({super.key, required this.deckId});

  final String deckId;

  @override
  ConsumerState<DeckEditScreen> createState() => _DeckEditScreenState();
}

class _DeckEditScreenState extends ConsumerState<DeckEditScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  Deck? _original;
  List<Flashcard> _cards = [];
  List<String> _tags = [];
  bool _dirty = false;
  bool _saving = false;
  bool _showIssues = false;
  String? _titleError;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  void _init(Deck deck) {
    _original = deck;
    _title.text = deck.title;
    _description.text = deck.description ?? '';
    _cards = [...deck.cards];
    _tags = [...deck.tags];
  }

  /// Appends cards from a CSV / Anki file (after the preview); saved with
  /// the rest of the edits.
  Future<void> _import() async {
    final picked = await pickDeckImport(
      context,
      ref,
      target: _title.text.trim().isEmpty ? null : _title.text.trim(),
    );
    if (picked == null || !mounted) return;
    final used = {for (final c in _cards) c.id};
    final newId = ref.read(idGeneratorProvider);
    final added = <Flashcard>[];
    for (final c in picked.result.items) {
      var card = c;
      while (!used.add(card.id)) {
        card = card.copyWith(id: newId());
      }
      added.add(card);
    }
    setState(() {
      _cards = [..._cards.where((c) => !isBlankCard(c)), ...added];
      _dirty = true;
    });
    showSnack(context, 'Added ${plural(added.length, 'card')} — save to keep');
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  /// Saves; returns true on success.
  Future<bool> _save() async {
    final original = _original;
    if (original == null || _saving) return false;
    final title = _title.text.trim();
    final cards = cardsForSave(_cards);
    setState(() {
      _titleError = title.isEmpty ? 'Give the deck a title.' : null;
      _showIssues = true;
    });
    if (title.isEmpty || cards == null) {
      final bad = _cards
          .where((c) => !isBlankCard(c) && cardIssues(c).isNotEmpty)
          .length;
      showSnack(
        context,
        cards == null
            ? 'Fill in both sides of ${plural(bad, 'card')} marked in red.'
            : 'Give the deck a title.',
      );
      return false;
    }
    setState(() => _saving = true);
    try {
      final description = _description.text.trim();
      final saved = await ref
          .read(deckRepositoryProvider)
          .update(
            original.copyWith(
              title: title,
              description: description.isEmpty ? null : description,
              cards: cards,
              tags: _tags,
            ),
          );
      if (!mounted) return true;
      setState(() {
        _original = saved;
        _cards = [...saved.cards];
        _tags = [...saved.tags];
        _dirty = false;
        _showIssues = false;
      });
      showSnack(context, 'Deck saved');
      return true;
    } on Object catch (e) {
      if (mounted) showSnack(context, errorText(e));
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmLeave() async {
    final choice = await showDialog<_LeaveChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: const Text('Save your changes before leaving?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Keep editing'),
          ),
          TextButton(
            key: const Key('discard-changes'),
            onPressed: () => Navigator.of(context).pop(_LeaveChoice.discard),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_LeaveChoice.save),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == _LeaveChoice.save && !await _save()) return;
    if (!mounted) return;
    setState(() => _dirty = false);
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.deck(widget.deckId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final deckAsync = ref.watch(deckProvider(widget.deckId));
    final userId = ref.watch(currentUserIdProvider);
    final loaded = deckAsync.value;
    if (_original == null && loaded != null) _init(loaded);

    final Widget body;
    if (_original != null) {
      body = _original!.isOwnedBy(userId)
          ? _editor(context)
          : const EmptyState(
              icon: Icons.lock_outline,
              title: 'Read-only deck',
              message:
                  'This deck is shared with you. Copy it to your account to '
                  'edit it.',
            );
    } else if (deckAsync.hasValue) {
      body = const NotFoundView(what: 'Deck');
    } else if (deckAsync.hasError) {
      body = EmptyState(
        icon: Icons.error_outline,
        title: 'Could not load the deck',
        message: errorText(deckAsync.error!),
      );
    } else {
      body = const ContentContainer(
        maxWidth: ContentWidth.form,
        child: Padding(
          padding: EdgeInsets.only(top: Insets.xl),
          child: LoadingSkeleton(rows: 4),
        ),
      );
    }

    final canEdit = _original?.isOwnedBy(userId) ?? false;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
            if (canEdit && _dirty) _save();
          },
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () {
            if (canEdit && _dirty) _save();
          },
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Edit deck'),
            actions: [
              if (canEdit)
                IconButton(
                  key: const Key('deck-edit-import'),
                  tooltip: 'Import cards (CSV / Anki)',
                  icon: const Icon(Icons.upload_file_outlined),
                  onPressed: _saving ? null : _import,
                ),
              if (canEdit)
                Padding(
                  padding: const EdgeInsets.only(right: Insets.md),
                  child: FilledButton.icon(
                    key: const Key('save-deck'),
                    onPressed: _saving || !_dirty ? null : _save,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: const Text('Save'),
                  ),
                ),
            ],
          ),
          body: body,
        ),
      ),
    );
  }

  Widget _editor(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final gutter = Breakpoints.gutter(context);
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('deck-title'),
          controller: _title,
          textCapitalization: TextCapitalization.sentences,
          style: theme.textTheme.titleLarge,
          decoration: InputDecoration(
            labelText: 'Title',
            errorText: _titleError,
          ),
          onChanged: (_) {
            if (_titleError != null) setState(() => _titleError = null);
            _markDirty();
          },
        ),
        Gaps.h12,
        TextField(
          key: const Key('deck-description'),
          controller: _description,
          minLines: 1,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Description (optional)',
          ),
          onChanged: (_) => _markDirty(),
        ),
        Gaps.h12,
        TagEditor(
          key: const Key('deck-tags'),
          tags: _tags,
          onChanged: (tags) => setState(() {
            _tags = tags;
            _dirty = true;
          }),
        ),
        SectionHeader(
          key: const Key('cards-header'),
          title: 'Cards',
          count: _cards.length,
          padding: const EdgeInsets.only(top: Insets.xl, bottom: Insets.md),
          trailing: _cards.length > 1
              ? Text(
                  'Drag to reorder',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.faintText,
                  ),
                )
              : null,
        ),
        if (_cards.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: Insets.sm),
            child: Text(
              'Add cards one by one, or paste many at once with Bulk add '
              '(front :: back per line).',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.mutedText,
              ),
            ),
          ),
      ],
    );
    return ContentContainer(
      maxWidth: ContentWidth.readable,
      padding: EdgeInsets.zero,
      child: DeckCardListEditor(
        cards: _cards,
        newId: ref.read(idGeneratorProvider),
        header: header,
        showIssues: _showIssues,
        padding: EdgeInsets.fromLTRB(gutter, Insets.xl, gutter, 96),
        onChanged: (list) => setState(() {
          _cards = list;
          _dirty = true;
        }),
      ),
    );
  }
}
