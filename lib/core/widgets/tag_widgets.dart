import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/data_providers.dart';
import '../../data/models/tags.dart';
import '../../data/repositories/organization_repository.dart';
import '../router/routes.dart';
import '../theme/app_colors.dart';
import '../theme/tokens.dart';
import 'error_message.dart';

/// Search query that filters by [tag] (`tag:biology`, `tag:"exam prep"`);
/// `SearchScreen` turns these tokens into tag filters.
String tagSearchQuery(String tag) =>
    tag.contains(RegExp(r'\s')) ? 'tag:"$tag"' : 'tag:$tag';

/// Opens global search filtered by [tag].
void openTagSearch(BuildContext context, String tag) {
  final router = GoRouter.maybeOf(context);
  router?.push(AppRoutes.searchFor(tagSearchQuery(tag)));
}

/// Quiet, read-only tag list (`#biology  #exam prep`). Tapping a tag runs
/// [onTap] (default: global search filtered by that tag). Renders nothing
/// when [tags] is empty.
class TagChips extends StatelessWidget {
  const TagChips({
    super.key,
    required this.tags,
    this.onTap,
    this.maxVisible,
    this.dense = false,
  });

  final List<String> tags;

  /// Tag tap; null = [openTagSearch].
  final ValueChanged<String>? onTap;

  /// Show at most this many, then "+N".
  final int? maxVisible;

  /// Smaller chips for list rows.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    final shown = maxVisible == null || tags.length <= maxVisible!
        ? tags
        : tags.take(maxVisible!).toList();
    final hidden = tags.length - shown.length;
    final colors = AppColors.of(context);
    final style =
        (dense
                ? Theme.of(context).textTheme.labelSmall
                : Theme.of(context).textTheme.labelMedium)
            ?.copyWith(color: colors.mutedText);
    return Wrap(
      spacing: Insets.xs,
      runSpacing: Insets.xs,
      children: [
        for (final tag in shown)
          _TagPill(
            key: ValueKey('tag-chip-$tag'),
            label: '#$tag',
            style: style,
            dense: dense,
            tooltip: 'Search #$tag',
            onTap: () => (onTap ?? (t) => openTagSearch(context, t))(tag),
          ),
        if (hidden > 0) _TagPill(label: '+$hidden', style: style, dense: dense),
      ],
    );
  }
}

class _TagPill extends StatelessWidget {
  const _TagPill({
    super.key,
    required this.label,
    required this.style,
    required this.dense,
    this.onTap,
    this.tooltip,
  });

  final String label;
  final TextStyle? style;
  final bool dense;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final pill = Material(
      color: colors.hover,
      shape: const RoundedRectangleBorder(borderRadius: Radii.smAll),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: dense ? Insets.xs + 2 : Insets.sm,
            vertical: dense ? 1 : Insets.xxs,
          ),
          child: Text(label, style: style),
        ),
      ),
    );
    return tooltip == null || onTap == null
        ? pill
        : Tooltip(message: tooltip, child: pill);
  }
}

/// Option of the tag autocomplete: an existing tag or "Create …".
@immutable
class _TagOption {
  const _TagOption(this.tag, {this.create = false});

  final String tag;
  final bool create;

  @override
  bool operator ==(Object other) =>
      other is _TagOption && other.tag == tag && other.create == create;

  @override
  int get hashCode => Object.hash(tag, create);
}

/// Edits a tag list: removable chips plus a field with autocomplete from
/// the tags in use ([suggestions], default: `allTagsProvider`) and
/// "Create …" for new ones. Enter picks the highlighted option, a comma
/// adds what was typed. Tags are normalized (`normalizeTags`) and capped
/// at [TagRules.maxTags]. Controlled: [onChanged] gets the new list.
class TagEditor extends ConsumerStatefulWidget {
  const TagEditor({
    super.key,
    required this.tags,
    required this.onChanged,
    this.suggestions,
    this.enabled = true,
    this.autofocus = false,
    this.hintText = 'Add a tag…',
  });

  final List<String> tags;
  final ValueChanged<List<String>> onChanged;

  /// Tags offered by the autocomplete; null = every tag in use.
  final List<String>? suggestions;
  final bool enabled;
  final bool autofocus;
  final String hintText;

  /// Key of the text field (tests).
  static const Key fieldKey = Key('tag-editor-field');

  @override
  ConsumerState<TagEditor> createState() => _TagEditorState();
}

class _TagEditorState extends ConsumerState<TagEditor> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _add(Iterable<String> raw) {
    final next = normalizeTags([...widget.tags, ...raw]);
    if (next.length > TagRules.maxTags) {
      showAppSnackBar(
        context,
        'At most ${TagRules.maxTags} tags.',
        isError: true,
      );
      return;
    }
    if (next.length != widget.tags.length) widget.onChanged(next);
  }

  void _remove(String tag) => widget.onChanged([
    for (final t in widget.tags)
      if (t != tag) t,
  ]);

  Iterable<_TagOption> _options(String input, List<String> all) {
    final query = normalizeTag(input);
    if (query == null) return const [];
    final current = widget.tags.toSet();
    final prefix = <_TagOption>[];
    final contains = <_TagOption>[];
    for (final t in all) {
      if (current.contains(t)) continue;
      if (t.startsWith(query)) {
        prefix.add(_TagOption(t));
      } else if (t.contains(query)) {
        contains.add(_TagOption(t));
      }
    }
    final matches = [...prefix, ...contains].take(8).toList();
    final exists = all.contains(query) || current.contains(query);
    return [...matches, if (!exists) _TagOption(query, create: true)];
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    final all =
        widget.suggestions ??
        [
          for (final c
              in ref.watch(allTagsProvider).value ?? const <TagCount>[])
            c.tag,
        ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.tags.isNotEmpty) ...[
          Wrap(
            spacing: Insets.xs,
            runSpacing: Insets.xs,
            children: [
              for (final tag in widget.tags)
                InputChip(
                  key: ValueKey('tag-editor-chip-$tag'),
                  label: Text('#$tag'),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onDeleted: widget.enabled ? () => _remove(tag) : null,
                  deleteButtonTooltipMessage: 'Remove $tag',
                ),
            ],
          ),
          Gaps.h8,
        ],
        RawAutocomplete<_TagOption>(
          textEditingController: _controller,
          focusNode: _focus,
          displayStringForOption: (_) => '',
          optionsBuilder: (value) => _options(value.text, all),
          onSelected: (option) {
            _add([option.tag]);
            _controller.clear();
            _focus.requestFocus();
          },
          fieldViewBuilder: (context, controller, focusNode, onSubmitted) =>
              TextField(
                key: TagEditor.fieldKey,
                controller: controller,
                focusNode: focusNode,
                enabled: widget.enabled,
                autofocus: widget.autofocus,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  prefixIcon: Icon(
                    Icons.sell_outlined,
                    size: 18,
                    color: colors.mutedText,
                  ),
                  isDense: true,
                ),
                onChanged: (text) {
                  if (!text.contains(',')) return;
                  _add(text.split(','));
                  controller.clear();
                },
                onSubmitted: (_) {
                  if (controller.text.trim().isEmpty) return;
                  onSubmitted();
                  // No option (e.g. tag already present): just clear.
                  if (controller.text.isNotEmpty) controller.clear();
                  focusNode.requestFocus();
                },
              ),
          optionsViewBuilder: (context, onSelected, options) => Align(
            alignment: Alignment.topLeft,
            child: Material(
              color: colors.card,
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: Radii.mdAll,
                side: BorderSide(color: colors.hairline),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: 260,
                  maxWidth: 360,
                ),
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: Insets.xs),
                  shrinkWrap: true,
                  children: [
                    for (final (i, option) in options.indexed)
                      Builder(
                        builder: (context) {
                          final highlighted =
                              AutocompleteHighlightedOption.of(context) == i;
                          return InkWell(
                            key: ValueKey(
                              option.create
                                  ? 'tag-create-${option.tag}'
                                  : 'tag-option-${option.tag}',
                            ),
                            onTap: () => onSelected(option),
                            child: Container(
                              color: highlighted ? colors.hover : null,
                              padding: const EdgeInsets.symmetric(
                                horizontal: Insets.md,
                                vertical: Insets.sm,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    option.create ? Icons.add : Icons.tag,
                                    size: 16,
                                    color: colors.mutedText,
                                  ),
                                  Gaps.w8,
                                  Flexible(
                                    child: Text(
                                      option.create
                                          ? 'Create "${option.tag}"'
                                          : option.tag,
                                      style: theme.textTheme.bodyMedium,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Dialog around a [TagEditor]; returns the new tags or null (cancelled).
Future<List<String>?> showTagEditorDialog(
  BuildContext context, {
  required List<String> initial,
  String title = 'Tags',
  List<String>? suggestions,
}) => showDialog<List<String>>(
  context: context,
  builder: (context) =>
      _TagDialog(initial: initial, title: title, suggestions: suggestions),
);

class _TagDialog extends StatefulWidget {
  const _TagDialog({
    required this.initial,
    required this.title,
    required this.suggestions,
  });

  final List<String> initial;
  final String title;
  final List<String>? suggestions;

  @override
  State<_TagDialog> createState() => _TagDialogState();
}

class _TagDialogState extends State<_TagDialog> {
  late List<String> _tags = [...widget.initial];

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 420,
      child: TagEditor(
        tags: _tags,
        suggestions: widget.suggestions,
        autofocus: true,
        onChanged: (next) => setState(() => _tags = next),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('tag-dialog-save'),
        onPressed: () => Navigator.of(context).pop(_tags),
        child: const Text('Save'),
      ),
    ],
  );
}

/// Opens [showTagEditorDialog] for a note / quiz / deck and saves the
/// result with `OrganizationRepository.setTags` (owner only; errors as a
/// snackbar). Returns true when saved.
Future<bool> editItemTags(
  BuildContext context,
  WidgetRef ref, {
  required TaggableKind kind,
  required String id,
  required List<String> tags,
}) async {
  final next = await showTagEditorDialog(context, initial: tags);
  if (next == null || !context.mounted) return false;
  try {
    await ref.read(organizationRepositoryProvider).setTags(kind, id, next);
    return true;
  } catch (e) {
    if (context.mounted) showErrorSnackBar(context, e);
    return false;
  }
}
