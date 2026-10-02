import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/widgets/design_system.dart';
import '../../../core/widgets/tag_widgets.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/deck.dart';
import '../../ai_generate/presentation/ai_generate_screen.dart';
import '../application/deck_io_actions.dart';
import '../domain/deck_format.dart';

/// [decks] with pinned ones first (each group keeps its order).
List<Deck> pinnedFirst(List<Deck> decks) => [
  for (final d in decks)
    if (d.pinned) d,
  for (final d in decks)
    if (!d.pinned) d,
];

/// Lists flashcard decks of a subject (when [noteId] is null: subject-level
/// decks) or of a note, pinned first, with open / new / import (CSV / Anki)
/// / AI-generate / study actions.
///
/// Cross-feature entry point: subject and note screens embed this; the decks
/// feature owns the implementation. Renders as a non-scrolling column, so
/// it can sit inside the parent's scroll view.
class DeckListSection extends ConsumerStatefulWidget {
  const DeckListSection({
    super.key,
    required this.subjectId,
    this.noteId,
    this.readOnly = false,
  });

  final String subjectId;
  final String? noteId;

  /// True when the parent is shared with (not owned by) the current user.
  final bool readOnly;

  @override
  ConsumerState<DeckListSection> createState() => _DeckListSectionState();
}

class _DeckListSectionState extends ConsumerState<DeckListSection> {
  bool _creating = false;

  Future<void> _create() async {
    setState(() => _creating = true);
    try {
      final deck = await ref
          .read(deckRepositoryProvider)
          .create(
            subjectId: widget.subjectId,
            noteId: widget.noteId,
            title: 'Untitled deck',
          );
      if (!mounted) return;
      await context.push(AppRoutes.deckEdit(deck.id));
    } on Object catch (e) {
      if (mounted) showSnack(context, errorText(e));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  void _generate() => context.push(
    AppRoutes.generate(
      kind: AiGenerateKind.deck,
      subjectId: widget.subjectId,
      noteId: widget.noteId,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final noteId = widget.noteId;
    final decks =
        (noteId == null
                ? ref
                      .watch(decksBySubjectProvider(widget.subjectId))
                      .whenData(
                        (l) => [
                          for (final d in l)
                            if (d.noteId == null) d,
                        ],
                      )
                : ref.watch(decksByNoteProvider(noteId)))
            .whenData(pinnedFirst);

    final actions = widget.readOnly
        ? null
        : <Widget>[
            AiGate(
              key: const Key('deck-generate-ai'),
              onReady: _generate,
              child: TextButton.icon(
                onPressed: _generate,
                icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                label: const Text('Generate with AI'),
              ),
            ),
            TextButton.icon(
              key: const Key('deck-import'),
              onPressed: () => importNewDeck(
                context,
                ref,
                subjectId: widget.subjectId,
                noteId: widget.noteId,
              ),
              icon: const Icon(Icons.upload_file_outlined, size: 18),
              label: const Text('Import'),
            ),
            TextButton.icon(
              key: const Key('deck-new'),
              onPressed: _creating ? null : _create,
              icon: _creating
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add, size: 18),
              label: const Text('New deck'),
            ),
          ];

    final count = decks.value?.length;
    final header = LayoutBuilder(
      builder: (context, constraints) {
        // Phones: actions go on their own line so the title never squeezes.
        final inline = constraints.maxWidth >= 480;
        final title = SectionHeader(
          title: 'Flashcards',
          count: count == null || count == 0 ? null : count,
          trailing: inline && actions != null
              ? Row(mainAxisSize: MainAxisSize.min, children: actions)
              : null,
        );
        if (inline || actions == null) return title;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            title,
            Wrap(spacing: Insets.xs, runSpacing: Insets.xs, children: actions),
            Gaps.h4,
          ],
        );
      },
    );

    final body = switch (decks) {
      AsyncValue(:final value?) when value.isEmpty => EmptyState(
        compact: true,
        icon: Icons.style_outlined,
        title: 'No flashcard decks yet',
        message: widget.readOnly
            ? null
            : noteId != null
            ? 'Create one or let AI turn the note into flashcards.'
            : 'Create one by hand or generate it with AI.',
      ),
      AsyncValue(:final value?) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final d in value) _DeckTile(deck: d)],
      ),
      AsyncValue(:final error?) => InfoBanner(
        kind: InfoBannerKind.error,
        message: 'Could not load decks: ${errorText(error)}',
      ),
      _ => const LoadingSkeleton(rows: 2, animate: false),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [header, body],
    );
  }
}

class _DeckTile extends ConsumerWidget {
  const _DeckTile({required this.deck});

  final Deck deck;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(deckStatsProvider(deck.id)).value;
    final count = deck.cards.length;
    final due = stats?.dueToday ?? 0;
    final fresh = stats?.newCount ?? 0;
    final parts = <String>[
      plural(count, 'card'),
      if (due > 0) '$due due',
      if (fresh > 0 && fresh < count) '$fresh new',
      if (count > 0 && stats != null && due == 0 && fresh < count) 'Up to date',
    ];
    final aiMade = deck.source?.provider != null;
    return ListRowTile(
      key: ValueKey('deck-row-${deck.id}'),
      leading: Tooltip(
        message: aiMade ? 'Generated with AI' : 'Flashcard deck',
        child: Icon(
          aiMade ? Icons.auto_awesome_outlined : Icons.style_outlined,
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              deck.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (deck.pinned)
            Padding(
              padding: const EdgeInsets.only(left: Insets.xs),
              child: Icon(
                Icons.push_pin,
                key: ValueKey('deck-pinned-${deck.id}'),
                size: 14,
                color: AppColors.of(context).faintText,
                semanticLabel: 'Pinned',
              ),
            ),
        ],
      ),
      subtitle: deck.tags.isEmpty
          ? Text(parts.join(' · '))
          : Wrap(
              spacing: Insets.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(parts.join(' · ')),
                TagChips(tags: deck.tags, dense: true, maxVisible: 3),
              ],
            ),
      onTap: () => context.push(AppRoutes.deck(deck.id)),
      actions: [
        if (count > 0)
          IconButton(
            key: ValueKey('deck-study-${deck.id}'),
            tooltip: 'Study',
            icon: const Icon(Icons.school_outlined),
            onPressed: () => context.push(AppRoutes.deckStudy(deck.id)),
          ),
      ],
    );
  }
}
