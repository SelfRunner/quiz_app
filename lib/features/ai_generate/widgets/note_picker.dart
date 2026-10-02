import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/design_system.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/models.dart';
import '../domain/generation_sources.dart';
import 'picker_panel.dart';

/// Searchable multi-select over every note the user can read (own + shared).
/// Returns the new selection, or null when cancelled.
Future<List<Note>?> showNotePicker(
  BuildContext context, {
  List<Note> selected = const [],
}) => showPickerPanel<List<Note>>(
  context,
  builder: (_) => NotePicker(initial: selected),
);

class NotePicker extends ConsumerStatefulWidget {
  const NotePicker({super.key, this.initial = const []});

  final List<Note> initial;

  @override
  ConsumerState<NotePicker> createState() => _NotePickerState();
}

class _NotePickerState extends ConsumerState<NotePicker> {
  final _search = TextEditingController();
  late final Map<String, Note> _selected = {
    for (final n in widget.initial) n.id: n,
  };

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggle(Note n) => setState(() {
    if (_selected.remove(n.id) == null) _selected[n.id] = n;
  });

  @override
  Widget build(BuildContext context) {
    final query = _search.text;
    final results = ref.watch(noteSearchProvider(query));
    final me = ref.watch(currentUserIdProvider);
    final count = _selected.length;
    return PickerScaffold(
      title: 'Add notes',
      header: TextField(
        key: const Key('note-picker-search'),
        controller: _search,
        autofocus: Breakpoints.isMedium(context),
        decoration: InputDecoration(
          hintText: 'Search your notes and notes shared with you',
          prefixIcon: const Icon(Icons.search, size: 20),
          isDense: true,
          suffixIcon: query.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(_search.clear),
                ),
        ),
        onChanged: (_) => setState(() {}),
      ),
      body: AsyncValueView<List<Note>>(
        value: results,
        loading: const LoadingSkeleton(rows: 5, subtitle: true),
        data: (notes) {
          if (notes.isEmpty) {
            return EmptyState(
              compact: true,
              icon: Icons.description_outlined,
              title: query.trim().isEmpty
                  ? 'No notes yet'
                  : 'No matching notes',
              message: query.trim().isEmpty
                  ? 'Notes you write or that are shared with you show up here.'
                  : 'Try a different search.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: Insets.md),
            itemCount: notes.length,
            itemBuilder: (context, i) {
              final n = notes[i];
              final selected = _selected.containsKey(n.id);
              return ListRowTile(
                key: ValueKey('note-option-${n.id}'),
                selected: selected,
                onTap: () => _toggle(n),
                leading: Checkbox(
                  value: selected,
                  onChanged: (_) => _toggle(n),
                ),
                title: Text(n.title.trim().isEmpty ? 'Untitled' : n.title),
                subtitle: _NoteSubtitle(note: n),
                trailing: n.isOwnedBy(me)
                    ? null
                    : const TagPill(
                        label: 'Shared',
                        icon: Icons.people_outline,
                      ),
              );
            },
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('note-picker-done'),
          onPressed: () => Navigator.of(context).pop(_selected.values.toList()),
          child: Text(
            count == 0 ? 'Done' : 'Use $count ${count == 1 ? 'note' : 'notes'}',
          ),
        ),
      ],
    );
  }
}

class _NoteSubtitle extends ConsumerWidget {
  const _NoteSubtitle({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subject = ref.watch(subjectProvider(note.subjectId)).value;
    final snippet = noteSnippet(note.contentMd);
    return Text(
      [
        if (subject != null) subject.title,
        if (snippet.isNotEmpty) snippet,
      ].join(' · '),
    );
  }
}
