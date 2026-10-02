import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../ai/ai_providers.dart';
import '../../../../ai/ai_tools_service.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/widgets/design_system.dart';
import '../../../../core/widgets/error_message.dart';
import '../../../../data/data_providers.dart';
import '../../../../data/models/models.dart';
import '../../../ai_generate/widgets/ai_error_card.dart';
import '../../application/note_ai_tools.dart';
import '../../application/note_document.dart';
import 'rich_note_markdown.dart';

/// What the AI tools act on and what they may change.
class NoteAiHost {
  const NoteAiHost({
    required this.currentMarkdown,
    required this.title,
    required this.subjectId,
    this.onReplace,
    this.onInsertBelow,
  });

  /// The note's current Markdown (the editor's unsaved text in the editor).
  final String Function() currentMarkdown;
  final String title;

  /// Subject for "Save as new note" (owners). Null = ask (read-only notes).
  final String? subjectId;

  /// Null for read-only notes (only "Save as new note" and "Copy").
  final Future<void> Function(String markdown)? onReplace;
  final Future<void> Function(String markdown)? onInsertBelow;

  bool get canEdit => onReplace != null && onInsertBelow != null;
}

/// "AI" menu (summarize, simplify, expand, translate, study guide, fix
/// formatting) gated by [AiGate].
class NoteAiMenuButton extends StatefulWidget {
  const NoteAiMenuButton({super.key, required this.host});

  final NoteAiHost host;

  @override
  State<NoteAiMenuButton> createState() => _NoteAiMenuButtonState();
}

class _NoteAiMenuButtonState extends State<NoteAiMenuButton> {
  final _menu = MenuController();

  void _toggle() => _menu.isOpen ? _menu.close() : _menu.open();

  Future<void> _run(NoteToolKind kind) async {
    final NoteTool tool;
    switch (kind) {
      case NoteToolKind.translate:
        final language = await showTranslateLanguageDialog(context);
        if (language == null || !mounted) return;
        tool = NoteTool.translate(language);
      case NoteToolKind.summarize:
        tool = NoteTool.summarize;
      case NoteToolKind.simplify:
        tool = NoteTool.simplify;
      case NoteToolKind.expand:
        tool = NoteTool.expand;
      case NoteToolKind.studyGuide:
        tool = NoteTool.studyGuide;
      case NoteToolKind.fixFormatting:
        tool = NoteTool.fixFormatting;
    }
    if (widget.host.currentMarkdown().trim().isEmpty) {
      showAppSnackBar(context, 'This note is empty. Write something first.');
      return;
    }
    await showNoteAiToolPanel(context, host: widget.host, tool: tool);
  }

  static IconData _icon(NoteToolKind kind) => switch (kind) {
    NoteToolKind.summarize => Icons.short_text,
    NoteToolKind.simplify => Icons.child_care_outlined,
    NoteToolKind.expand => Icons.unfold_more,
    NoteToolKind.translate => Icons.translate,
    NoteToolKind.studyGuide => Icons.school_outlined,
    NoteToolKind.fixFormatting => Icons.format_paint_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return MenuAnchor(
      controller: _menu,
      alignmentOffset: const Offset(-180, 0),
      menuChildren: [
        for (final kind in NoteToolKind.values)
          MenuItemButton(
            key: Key('ai-tool-${kind.name}'),
            leadingIcon: Icon(_icon(kind), size: 18),
            onPressed: () => unawaited(_run(kind)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Insets.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(kind.label),
                  Text(
                    kind.description,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: colors.mutedText),
                  ),
                ],
              ),
            ),
          ),
      ],
      builder: (context, controller, _) => AiGate(
        onReady: _toggle,
        child: IconButton(
          key: const Key('note-ai-menu'),
          tooltip: 'AI tools',
          icon: const Icon(Icons.auto_fix_high_outlined),
          onPressed: _toggle,
        ),
      ),
    );
  }
}

/// Asks for a target language.
Future<String?> showTranslateLanguageDialog(BuildContext context) =>
    showDialog<String>(
      context: context,
      builder: (_) => const _TranslateDialog(),
    );

class _TranslateDialog extends StatefulWidget {
  const _TranslateDialog();

  @override
  State<_TranslateDialog> createState() => _TranslateDialogState();
}

class _TranslateDialogState extends State<_TranslateDialog> {
  final _other = TextEditingController();
  String? _selected;

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  String? get _language {
    final other = _other.text.trim();
    return other.isNotEmpty ? other : _selected;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Translate note'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: Insets.sm,
              runSpacing: Insets.sm,
              children: [
                for (final language in kTranslateLanguages)
                  ChoiceChip(
                    key: Key('lang-$language'),
                    label: Text(language),
                    selected: _selected == language && _other.text.isEmpty,
                    onSelected: (_) => setState(() {
                      _selected = language;
                      _other.clear();
                    }),
                  ),
              ],
            ),
            Gaps.h16,
            TextField(
              key: const Key('lang-other'),
              controller: _other,
              decoration: const InputDecoration(
                labelText: 'Other language',
                hintText: 'e.g. Swahili',
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (_language != null) Navigator.of(context).pop(_language);
              },
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('lang-translate'),
        onPressed: _language == null
            ? null
            : () => Navigator.of(context).pop(_language),
        child: const Text('Translate'),
      ),
    ],
  );
}

sealed class _Outcome {
  const _Outcome();
}

class _Replace extends _Outcome {
  const _Replace(this.markdown);
  final String markdown;
}

class _Insert extends _Outcome {
  const _Insert(this.markdown);
  final String markdown;
}

class _Saved extends _Outcome {
  const _Saved(this.note);
  final Note note;
}

/// Runs [tool] on the host's note and shows the result in a side panel
/// (wide screens) or bottom sheet, then applies the chosen action.
Future<void> showNoteAiToolPanel(
  BuildContext context, {
  required NoteAiHost host,
  required NoteTool tool,
}) async {
  final markdown = host.currentMarkdown();
  final panel = NoteAiToolPanel(host: host, tool: tool, original: markdown);
  final _Outcome? outcome;
  if (Breakpoints.isExpanded(context)) {
    outcome = await showGeneralDialog<_Outcome>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.black26,
      transitionDuration: Motion.medium,
      pageBuilder: (dialogContext, _, _) => Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: AppColors.of(dialogContext).card,
          child: SizedBox(
            width: 560,
            height: double.infinity,
            child: SafeArea(child: panel),
          ),
        ),
      ),
      transitionBuilder: (_, animation, _, child) => SlideTransition(
        position: Tween(
          begin: const Offset(0.15, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
        child: FadeTransition(opacity: animation, child: child),
      ),
    );
  } else {
    outcome = await showModalBottomSheet<_Outcome>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.88,
        child: panel,
      ),
    );
  }
  if (!context.mounted || outcome == null) return;
  switch (outcome) {
    case _Replace(:final markdown):
      await host.onReplace?.call(markdown);
    case _Insert(:final markdown):
      await host.onInsertBelow?.call(markdown);
    case _Saved(:final note):
      showAppSnackBar(
        context,
        'Saved as "${note.title}"',
        action: SnackBarAction(
          label: 'Open',
          onPressed: () => context.push(AppRoutes.note(note.id)),
        ),
      );
  }
}

/// Runs an AI note tool and previews the result (before/after) with
/// actions: replace, insert below, save as new note, copy.
class NoteAiToolPanel extends ConsumerStatefulWidget {
  const NoteAiToolPanel({
    super.key,
    required this.host,
    required this.tool,
    required this.original,
  });

  final NoteAiHost host;
  final NoteTool tool;
  final String original;

  @override
  ConsumerState<NoteAiToolPanel> createState() => _NoteAiToolPanelState();
}

class _NoteAiToolPanelState extends ConsumerState<NoteAiToolPanel> {
  int _run = 0;
  NoteToolResult? _result;
  Object? _error;
  bool _showOriginal = false;
  bool _saving = false;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    _run++; // Ignore a result that arrives after closing.
    super.dispose();
  }

  Future<void> _start() async {
    final run = ++_run;
    setState(() {
      _result = null;
      _error = null;
      _showOriginal = false;
    });
    try {
      final result = await ref
          .read(aiToolsServiceProvider)
          .transformNote(
            widget.original,
            widget.tool,
            title: widget.host.title,
          );
      if (!mounted || run != _run) return;
      setState(() => _result = result);
    } catch (e) {
      if (!mounted || run != _run) return;
      setState(() => _error = e);
    }
  }

  void _close([_Outcome? outcome]) => Navigator.of(context).pop(outcome);

  Future<void> _copy() async {
    final result = _result;
    if (result == null) return;
    await Clipboard.setData(ClipboardData(text: result.markdown));
    if (!mounted) return;
    setState(() => _copied = true);
  }

  Future<void> _saveAsNew() async {
    final result = _result;
    if (result == null || _saving) return;
    final subjectId = widget.host.subjectId ?? await pickTargetSubject(context);
    if (subjectId == null || !mounted) return;
    setState(() => _saving = true);
    try {
      final note = await ref
          .read(noteRepositoryProvider)
          .create(
            subjectId: subjectId,
            title: noteToolNewTitle(
              widget.host.title,
              widget.tool,
              suggested: result.title,
            ),
            contentMd: result.markdown,
          );
      if (mounted) _close(_Saved(note));
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showErrorSnackBar(context, e, prefix: 'Could not save');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(Insets.xl, Insets.sm, Insets.sm, 0),
      child: Row(
        children: [
          Icon(Icons.auto_fix_high_outlined, size: 18, color: colors.mutedText),
          Gaps.w8,
          Expanded(
            child: Text(
              noteToolTitle(widget.tool),
              style: theme.textTheme.titleMedium,
            ),
          ),
          IconButton(
            key: const Key('ai-panel-close'),
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: _close,
          ),
        ],
      ),
    );

    final Widget body;
    final result = _result;
    final error = _error;
    if (error != null) {
      body = _ErrorBody(error: error, onRetry: _start);
    } else if (result == null) {
      body = _ProgressBody(label: widget.tool.kind.progress, onCancel: _close);
    } else {
      body = _resultBody(context, result);
    }
    return Column(
      key: const Key('ai-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Expanded(child: body),
      ],
    );
  }

  Widget _resultBody(BuildContext context, NoteToolResult result) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final shown = _showOriginal ? widget.original : result.markdown;
    final before = NoteDocument.wordCount(widget.original);
    final after = NoteDocument.wordCount(result.markdown);
    final canEdit = widget.host.canEdit;

    final actions = Wrap(
      spacing: Insets.sm,
      runSpacing: Insets.sm,
      alignment: WrapAlignment.end,
      children: [
        TextButton.icon(
          key: const Key('ai-copy'),
          onPressed: _copy,
          icon: Icon(_copied ? Icons.check : Icons.content_copy, size: 18),
          label: Text(_copied ? 'Copied' : 'Copy'),
        ),
        OutlinedButton.icon(
          key: const Key('ai-save-new'),
          onPressed: _saving ? null : _saveAsNew,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.note_add_outlined, size: 18),
          label: const Text('Save as new note'),
        ),
        if (canEdit) ...[
          FilledButton.tonalIcon(
            key: const Key('ai-insert'),
            onPressed: () => _close(_Insert(result.markdown)),
            icon: const Icon(Icons.vertical_align_bottom, size: 18),
            label: const Text('Insert below'),
          ),
          FilledButton.icon(
            key: const Key('ai-replace'),
            onPressed: () => _close(_Replace(result.markdown)),
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: const Text('Replace note'),
          ),
        ],
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.xl,
            Insets.sm,
            Insets.xl,
            Insets.sm,
          ),
          child: Wrap(
            spacing: Insets.md,
            runSpacing: Insets.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<bool>(
                key: const Key('ai-toggle'),
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(value: false, label: Text('Result')),
                  ButtonSegment(value: true, label: Text('Original')),
                ],
                selected: {_showOriginal},
                onSelectionChanged: (s) =>
                    setState(() => _showOriginal = s.first),
              ),
              Text(
                '$before → $after words',
                key: const Key('ai-word-delta'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.mutedText,
                ),
              ),
            ],
          ),
        ),
        if (result.inputTruncated)
          const Padding(
            padding: EdgeInsets.fromLTRB(Insets.xl, 0, Insets.xl, Insets.sm),
            child: InfoBanner(
              kind: InfoBannerKind.warning,
              message:
                  'This note is long, so only part of it was used for this '
                  'result.',
            ),
          ),
        Divider(height: 1, color: colors.hairline),
        Expanded(
          child: ColoredBox(
            color: _showOriginal ? colors.sidebar : Colors.transparent,
            child: SingleChildScrollView(
              key: const Key('ai-preview'),
              padding: const EdgeInsets.all(Insets.xl),
              child: RichNoteMarkdown(
                key: ValueKey(_showOriginal),
                data: shown,
              ),
            ),
          ),
        ),
        Divider(height: 1, color: colors.hairline),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.lg,
            Insets.md,
            Insets.lg,
            Insets.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!canEdit)
                Padding(
                  padding: const EdgeInsets.only(bottom: Insets.sm),
                  child: Text(
                    'This note is read-only. Save the result as a new note in '
                    'one of your subjects.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.mutedText,
                    ),
                  ),
                ),
              actions,
            ],
          ),
        ),
      ],
    );
  }
}

class _ProgressBody extends StatelessWidget {
  const _ProgressBody({required this.label, required this.onCancel});

  final String label;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Insets.xl),
        child: Column(
          key: const Key('ai-progress'),
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 200,
              child: LinearProgressIndicator(minHeight: 3),
            ),
            Gaps.h16,
            Text(label, style: theme.textTheme.bodyLarge),
            Gaps.h4,
            Text(
              'This can take up to a minute for long notes.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.mutedText,
              ),
            ),
            Gaps.h16,
            OutlinedButton(
              key: const Key('ai-cancel'),
              onPressed: onCancel,
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final friendly = describeAiError(error);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Insets.xl),
      child: Column(
        key: const Key('ai-error'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoBanner(
            kind: InfoBannerKind.error,
            title: friendly.title,
            message: [
              friendly.message,
              if (friendly.hint != null) friendly.hint!,
            ].join('\n\n'),
          ),
          Gaps.h16,
          Wrap(
            alignment: WrapAlignment.end,
            spacing: Insets.sm,
            children: [
              if (friendly.openSettings)
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.push(AppRoutes.settings);
                  },
                  child: const Text('Open settings'),
                ),
              if (friendly.canRetry)
                FilledButton.tonal(
                  key: const Key('ai-retry'),
                  onPressed: onRetry,
                  child: const Text('Try again'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Asks which of the user's subjects receives a copy (read-only notes).
/// Offers to create a subject when the user has none.
Future<String?> pickTargetSubject(BuildContext context) => showDialog<String>(
  context: context,
  builder: (_) => const _SubjectPickerDialog(),
);

class _SubjectPickerDialog extends ConsumerStatefulWidget {
  const _SubjectPickerDialog();

  @override
  ConsumerState<_SubjectPickerDialog> createState() =>
      _SubjectPickerDialogState();
}

class _SubjectPickerDialogState extends ConsumerState<_SubjectPickerDialog> {
  final _name = TextEditingController();
  bool _creating = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty || _creating) return;
    setState(() => _creating = true);
    try {
      final subject = await ref
          .read(subjectRepositoryProvider)
          .create(title: name);
      if (mounted) Navigator.of(context).pop(subject.id);
    } catch (e) {
      if (mounted) {
        setState(() => _creating = false);
        showErrorSnackBar(context, e, prefix: 'Could not create subject');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final subjects = ref.watch(subjectsProvider);
    final userId = ref.watch(currentUserIdProvider);
    final own = (subjects.value ?? const <Subject>[])
        .where((s) => s.isOwnedBy(userId))
        .toList();
    return AlertDialog(
      title: const Text('Save to subject'),
      content: SizedBox(
        width: 400,
        child: subjects.isLoading && own.isEmpty
            ? const LoadingSkeleton(rows: 3, animate: false)
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final s in own)
                      ListTile(
                        key: Key('pick-subject-${s.id}'),
                        leading: SubjectColorDot(color: s.color),
                        title: Text(s.title),
                        shape: const RoundedRectangleBorder(
                          borderRadius: Radii.mdAll,
                        ),
                        onTap: () => Navigator.of(context).pop(s.id),
                      ),
                    if (own.isNotEmpty) const Divider(),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const Key('pick-subject-new'),
                            controller: _name,
                            decoration: const InputDecoration(
                              hintText: 'New subject name',
                              isDense: true,
                            ),
                            onSubmitted: (_) => _create(),
                          ),
                        ),
                        Gaps.w8,
                        TextButton(
                          onPressed: _creating ? null : _create,
                          child: const Text('Create'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
