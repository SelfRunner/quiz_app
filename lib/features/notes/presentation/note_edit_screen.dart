import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/widgets/design_system.dart';
import '../../../core/widgets/error_message.dart';
import '../../../core/widgets/tag_widgets.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/models.dart';
import '../../../data/repositories/organization_repository.dart';
import '../application/markdown_editing.dart';
import '../application/note_ai_tools.dart';
import '../application/note_document.dart';
import '../application/note_image_picker.dart';
import 'widgets/markdown_toolbar.dart';
import 'widgets/note_ai_tools.dart';
import 'widgets/rich_note_markdown.dart';

/// Default title given to notes created from "New note".
const String kUntitledNoteTitle = 'Untitled note';

enum _EditorMode { write, split, preview }

enum _SaveState { saved, dirty, saving, failed }

enum _LeaveChoice { save, discard }

/// Markdown note editor: toolbar, image insertion, write/preview (split view
/// on wide screens), debounced autosave, explicit save (Ctrl+S) and an
/// unsaved-changes guard.
class NoteEditScreen extends ConsumerStatefulWidget {
  const NoteEditScreen({super.key, required this.noteId});

  final String noteId;

  /// Delay after the last keystroke before autosaving.
  static const Duration autosaveDelay = Duration(seconds: 2);

  @override
  ConsumerState<NoteEditScreen> createState() => _NoteEditScreenState();
}

class _NoteEditScreenState extends ConsumerState<NoteEditScreen> {
  final _title = TextEditingController();
  final _content = TextEditingController();
  final _contentFocus = FocusNode();

  Note? _note;
  Object? _loadError;
  bool _loading = true;

  /// Last persisted values, to compute dirtiness.
  String _savedTitle = '';
  String _savedContent = '';
  _SaveState _saveState = _SaveState.saved;
  Timer? _autosave;
  Future<void>? _saving;
  bool _imageBusy = false;
  _EditorMode? _mode;
  bool _focusMode = false;

  bool get _dirty =>
      _title.text != _savedTitle || _content.text != _savedContent;

  @override
  void initState() {
    super.initState();
    _title.addListener(_onChanged);
    _content.addListener(_onChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    _autosave?.cancel();
    _title.dispose();
    _content.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final note = await ref
          .read(noteRepositoryProvider)
          .getById(widget.noteId);
      if (!mounted) return;
      setState(() {
        _note = note;
        _loading = false;
        if (note != null) {
          _savedTitle = note.title;
          _savedContent = note.contentMd;
          _title.text = note.title;
          _content.text = note.contentMd;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  void _onChanged() {
    if (_note == null) return;
    final dirty = _dirty;
    if (dirty && _saveState != _SaveState.saving) {
      _autosave?.cancel();
      _autosave = Timer(NoteEditScreen.autosaveDelay, () => unawaited(_save()));
    }
    final next = _saveState == _SaveState.saving
        ? _SaveState.saving
        : (dirty ? _SaveState.dirty : _SaveState.saved);
    if (next != _saveState) setState(() => _saveState = next);
  }

  /// Saves if dirty. Returns true when everything is persisted.
  Future<bool> _save({bool showConfirmation = false}) async {
    _autosave?.cancel();
    final running = _saving;
    if (running != null) await running;
    final note = _note;
    if (note == null) return false;
    if (!_dirty) {
      if (showConfirmation && mounted) showAppSnackBar(context, 'Saved');
      return true;
    }
    final title = _title.text.trim().isEmpty
        ? kUntitledNoteTitle
        : _title.text.trim();
    final content = _content.text;
    final snapshotTitle = _title.text;
    setState(() => _saveState = _SaveState.saving);
    final completer = Completer<void>();
    _saving = completer.future;
    try {
      final repo = ref.read(noteRepositoryProvider);
      // Tags / pin may have changed elsewhere (tag dialog, another screen):
      // keep the stored values instead of the ones loaded with the editor.
      final latest = await repo.getById(note.id);
      final saved = await repo.update(
        note.copyWith(
          title: title,
          contentMd: content,
          tags: latest?.tags ?? note.tags,
          pinned: latest?.pinned ?? note.pinned,
        ),
      );
      _note = saved;
      _savedTitle = snapshotTitle;
      _savedContent = content;
      if (mounted) {
        setState(
          () => _saveState = _dirty ? _SaveState.dirty : _SaveState.saved,
        );
        if (_dirty) _onChanged(); // Typed during save: schedule again.
        if (showConfirmation) showAppSnackBar(context, 'Saved');
      }
      return true;
    } catch (e) {
      if (mounted) {
        setState(() => _saveState = _SaveState.failed);
        showErrorSnackBar(context, e, prefix: 'Could not save');
      }
      return false;
    } finally {
      _saving = null;
      completer.complete();
    }
  }

  /// A note created via "New note" and left untouched is discarded on exit.
  bool get _isPristineNewNote {
    final note = _note;
    return note != null &&
        note.createdAt == note.updatedAt &&
        note.contentMd.isEmpty &&
        note.title == kUntitledNoteTitle &&
        _content.text.trim().isEmpty &&
        (_title.text.trim().isEmpty || _title.text == kUntitledNoteTitle);
  }

  Future<void> _handleBack() async {
    final note = _note;
    if (note != null && _isPristineNewNote) {
      try {
        await ref.read(noteRepositoryProvider).delete(note.id);
        if (mounted) showAppSnackBar(context, 'Empty note discarded');
      } catch (_) {
        // Keep it; not worth bothering the user.
      }
      _leave();
      return;
    }
    if (!_dirty) {
      _leave();
      return;
    }
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
    if (choice == _LeaveChoice.discard) {
      _autosave?.cancel();
      _title.text = _savedTitle;
      _content.text = _savedContent;
    }
    _leave();
  }

  void _leave() {
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.note(widget.noteId));
    }
  }

  Future<void> _insertLink() async {
    final sel = _content.selection;
    final selected = sel.isValid && !sel.isCollapsed
        ? sel.textInside(_content.text)
        : '';
    final result = await showInsertLinkDialog(context, initialLabel: selected);
    if (result == null || !mounted) return;
    _content.value = MarkdownEditing.link(
      _content.value,
      url: result.url,
      label: result.label,
    );
    _contentFocus.requestFocus();
  }

  Future<void> _insertImage() async {
    final note = _note;
    if (note == null || _imageBusy) return;
    setState(() => _imageBusy = true);
    try {
      final picked = await ref.read(noteImagePickerProvider).pickImage();
      if (picked == null || !mounted) return;
      if (picked.bytes.lengthInBytes > 10 * 1024 * 1024) {
        throw const ValidationException(
          'That image is larger than 10 MB. Please pick a smaller one.',
        );
      }
      final imageRef = await ref
          .read(imageStoreProvider)
          .saveNoteImage(
            noteId: note.id,
            bytes: picked.bytes,
            extension: picked.extension,
          );
      if (!mounted) return;
      final alt = _altFromName(picked.name);
      _content.value = MarkdownEditing.image(
        _content.value,
        url: imageRef.markdownUrl,
        alt: alt,
      );
      _contentFocus.requestFocus();
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e, prefix: 'Could not add image');
    } finally {
      if (mounted) setState(() => _imageBusy = false);
    }
  }

  static String _altFromName(String? name) {
    if (name == null || name.isEmpty) return 'image';
    final dot = name.lastIndexOf('.');
    final base = (dot > 0 ? name.substring(0, dot) : name)
        .replaceAll(RegExp(r'[\[\]()]'), '')
        .trim();
    return base.isEmpty ? 'image' : base;
  }

  void _wrap(String marker, String placeholder) {
    _content.value = MarkdownEditing.wrap(
      _content.value,
      marker,
      marker,
      placeholder: placeholder,
    );
    _contentFocus.requestFocus();
  }

  void _list(ListKind kind) {
    _content.value = MarkdownEditing.toggleList(_content.value, kind);
    _contentFocus.requestFocus();
  }

  /// Tab / Shift+Tab indent list items; elsewhere Tab keeps its default.
  KeyEventResult _onEditorKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.tab) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed || keys.isMetaPressed || keys.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final next = MarkdownEditing.indentList(
      _content.value,
      outdent: keys.isShiftPressed,
    );
    if (next == null) return KeyEventResult.ignored;
    _content.value = next;
    return KeyEventResult.handled;
  }

  void _toggleFocusMode() {
    setState(() => _focusMode = !_focusMode);
    _contentFocus.requestFocus();
  }

  void _toggleTaskInEditor(int index, bool checked) {
    final updated = NoteDocument.setTask(
      _content.text,
      index,
      checked: checked,
    );
    if (updated == null) return;
    final selection = _content.selection;
    _content.value = TextEditingValue(
      text: updated,
      selection: selection.isValid && selection.end <= updated.length
          ? selection
          : TextSelection.collapsed(offset: updated.length),
    );
  }

  NoteAiHost _aiHost(Note note) => NoteAiHost(
    currentMarkdown: () => _content.text,
    title: _title.text.trim().isEmpty ? note.title : _title.text.trim(),
    subjectId: note.subjectId,
    onReplace: (markdown) async {
      _content.value = TextEditingValue(
        text: markdown,
        selection: TextSelection.collapsed(offset: markdown.length),
      );
      if (mounted) showAppSnackBar(context, 'Note content replaced');
    },
    onInsertBelow: (markdown) async {
      final text = appendMarkdown(_content.text, markdown);
      _content.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      if (mounted) showAppSnackBar(context, 'Inserted below');
    },
  );

  Map<ShortcutActivator, VoidCallback> get _shortcuts {
    final bindings = <ShortcutActivator, VoidCallback>{};
    void both(
      LogicalKeyboardKey key,
      VoidCallback action, {
      bool shift = false,
    }) {
      bindings[SingleActivator(key, control: true, shift: shift)] = action;
      bindings[SingleActivator(key, meta: true, shift: shift)] = action;
    }

    both(
      LogicalKeyboardKey.keyS,
      () => unawaited(_save(showConfirmation: true)),
    );
    both(LogicalKeyboardKey.keyB, () => _wrap('**', 'bold'));
    both(LogicalKeyboardKey.keyI, () => _wrap('_', 'italic'));
    both(LogicalKeyboardKey.keyE, () => _wrap('`', 'code'));
    both(LogicalKeyboardKey.keyK, () => unawaited(_insertLink()));
    // Shift+digit may report the shifted character on some layouts.
    for (final (keys, kind) in [
      (
        [LogicalKeyboardKey.digit7, LogicalKeyboardKey.ampersand],
        ListKind.numbered,
      ),
      (
        [LogicalKeyboardKey.digit8, LogicalKeyboardKey.asterisk],
        ListKind.bullet,
      ),
      (
        [LogicalKeyboardKey.digit9, LogicalKeyboardKey.parenthesisLeft],
        ListKind.task,
      ),
    ]) {
      for (final key in keys) {
        both(key, () => _list(kind), shift: true);
      }
    }
    both(LogicalKeyboardKey.keyF, _toggleFocusMode, shift: true);
    if (_focusMode) {
      bindings[const SingleActivator(LogicalKeyboardKey.escape)] =
          _toggleFocusMode;
    }
    return bindings;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit note')),
        body: const ContentContainer(child: LoadingSkeleton(leading: false)),
      );
    }
    final note = _note;
    if (note == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit note')),
        body: _loadError != null
            ? ErrorView(error: _loadError)
            : const NotFoundView(what: 'Note'),
      );
    }
    if (!note.isOwnedBy(ref.watch(currentUserIdProvider))) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit note')),
        body: const EmptyState(
          icon: Icons.lock_outline,
          title: 'Read-only note',
          message:
              'This note was shared with you. Copy it to your account to edit '
              'your own version.',
        ),
      );
    }

    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final wide = Breakpoints.isExpanded(context);
    final tags = ref.watch(noteProvider(note.id)).value?.tags ?? note.tags;
    void editTags() => unawaited(
      editItemTags(
        context,
        ref,
        kind: TaggableKind.note,
        id: note.id,
        tags: tags,
      ),
    );
    final tagRow = Padding(
      padding: const EdgeInsets.only(bottom: Insets.sm),
      child: Wrap(
        key: const Key('note-editor-tags'),
        spacing: Insets.xs,
        runSpacing: Insets.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          TagChips(tags: tags, dense: true, onTap: (_) => editTags()),
          TextButton.icon(
            key: const Key('note-editor-tags-button'),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 26),
              visualDensity: VisualDensity.compact,
              foregroundColor: colors.mutedText,
              textStyle: theme.textTheme.labelMedium,
            ),
            onPressed: editTags,
            icon: Icon(
              tags.isEmpty ? Icons.sell_outlined : Icons.edit_outlined,
              size: 14,
            ),
            label: Text(tags.isEmpty ? 'Add tags' : 'Edit tags'),
          ),
        ],
      ),
    );
    final canFocusMode = Breakpoints.isMedium(context);
    final focusMode = _focusMode && canFocusMode;
    final mode = focusMode
        ? _EditorMode.write
        : (_mode ?? (wide ? _EditorMode.split : _EditorMode.write));
    final effectiveMode = !wide && mode == _EditorMode.split
        ? _EditorMode.write
        : mode;

    final hairline = Divider(height: 1, color: colors.hairline);
    final split = effectiveMode == _EditorMode.split;
    // Single-pane modes keep a readable line length; split uses the width.
    Widget pane(Widget child) => split
        ? child
        : ContentContainer(
            maxWidth: focusMode ? 760 : ContentWidth.readable,
            child: child,
          );

    final focusToggle = canFocusMode
        ? IconButton(
            key: const Key('note-focus-mode'),
            tooltip: focusMode
                ? 'Exit focus mode (Esc)'
                : 'Focus mode (${shortcutLabel('F', shift: true)})',
            icon: Icon(
              focusMode ? Icons.fullscreen_exit : Icons.fullscreen,
              size: 18,
            ),
            color: colors.mutedText,
            visualDensity: VisualDensity.compact,
            onPressed: _toggleFocusMode,
          )
        : null;

    final toolbar = MarkdownToolbar(
      controller: _content,
      focusNode: _contentFocus,
      onInsertLink: _insertLink,
      onInsertImage: _insertImage,
      imageBusy: _imageBusy,
      trailing: [
        if (focusToggle != null) ...[const _ToolbarGap(), focusToggle],
      ],
    );

    final stats = ListenableBuilder(
      listenable: _content,
      builder: (context, _) => Text(
        NoteDocument.statsLabel(_content.text),
        key: const Key('note-word-count'),
        style: theme.textTheme.labelSmall?.copyWith(color: colors.faintText),
      ),
    );

    final editor = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: _onEditorKey,
            child: TextField(
              key: const Key('note-content'),
              controller: _content,
              focusNode: _contentFocus,
              expands: true,
              maxLines: null,
              minLines: null,
              keyboardType: TextInputType.multiline,
              textAlignVertical: TextAlignVertical.top,
              inputFormatters: const [ListContinuationFormatter()],
              style: theme.textTheme.bodyLarge?.copyWith(
                fontFamily: focusMode ? null : 'monospace',
                fontSize: focusMode ? 17 : 14.5,
                height: focusMode ? 1.75 : 1.6,
              ),
              decoration: InputDecoration(
                hintText:
                    'Write in Markdown… e.g. ## Heading, **bold**, - list, '
                    r'$x^2$',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: split ? Insets.lg : 0,
                  vertical: focusMode ? Insets.xxl : Insets.lg,
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            split ? Insets.lg : 0,
            Insets.xs,
            split ? Insets.lg : 0,
            Insets.sm,
          ),
          child: stats,
        ),
      ],
    );

    final preview = ListenableBuilder(
      listenable: _content,
      builder: (context, _) => _content.text.trim().isEmpty
          ? const EmptyState(
              icon: Icons.preview_outlined,
              title: 'Nothing to preview',
              message: 'Start writing to see the rendered note.',
            )
          : SingleChildScrollView(
              key: const Key('note-preview'),
              padding: EdgeInsets.symmetric(
                horizontal: split ? Insets.xl : 0,
                vertical: Insets.lg,
              ),
              child: RichNoteMarkdown(
                data: _content.text,
                onToggleTask: _toggleTaskInEditor,
              ),
            ),
    );

    final body = switch (effectiveMode) {
      _EditorMode.write => pane(editor),
      _EditorMode.preview => pane(preview),
      _EditorMode.split => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: editor),
          VerticalDivider(width: 1, color: colors.hairline),
          Expanded(
            child: ColoredBox(color: colors.sidebar, child: preview),
          ),
        ],
      ),
    };

    final Widget scaffold;
    if (focusMode) {
      scaffold = Scaffold(
        key: const Key('note-focus-scaffold'),
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(child: body),
              Positioned(
                top: Insets.sm,
                right: Insets.md,
                child: Row(
                  children: [
                    _SaveIndicator(state: _saveState),
                    Gaps.w8,
                    TextButton.icon(
                      key: const Key('note-exit-focus'),
                      onPressed: _toggleFocusMode,
                      icon: const Icon(Icons.fullscreen_exit, size: 18),
                      label: const Text('Exit focus'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      scaffold = Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: () => unawaited(_handleBack())),
          title: const Text('Edit note'),
          actions: [
            _SaveIndicator(state: _saveState),
            const SizedBox(width: 8),
            NoteAiMenuButton(host: _aiHost(note)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: SegmentedButton<_EditorMode>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [
                  const ButtonSegment(
                    value: _EditorMode.write,
                    icon: Icon(Icons.edit_outlined),
                    tooltip: 'Write',
                  ),
                  if (wide)
                    const ButtonSegment(
                      value: _EditorMode.split,
                      icon: Icon(Icons.vertical_split_outlined),
                      tooltip: 'Split view',
                    ),
                  const ButtonSegment(
                    value: _EditorMode.preview,
                    icon: Icon(Icons.visibility_outlined),
                    tooltip: 'Preview',
                  ),
                ],
                selected: {effectiveMode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
            ),
            IconButton(
              key: const Key('note-save'),
              tooltip: 'Save (${shortcutLabel('S')})',
              icon: const Icon(Icons.save_outlined),
              onPressed: _saveState == _SaveState.saving
                  ? null
                  : () => unawaited(_save(showConfirmation: true)),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ContentContainer(
              maxWidth: split ? double.infinity : ContentWidth.readable,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const Key('note-title'),
                    controller: _title,
                    style: theme.textTheme.headlineSmall,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => _contentFocus.requestFocus(),
                    onTap: () {
                      // Select the placeholder title for quick replacement.
                      if (_title.text == kUntitledNoteTitle) {
                        _title.selection = TextSelection(
                          baseOffset: 0,
                          extentOffset: _title.text.length,
                        );
                      }
                    },
                    decoration: const InputDecoration(
                      hintText: 'Title',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.symmetric(vertical: Insets.md),
                    ),
                  ),
                  tagRow,
                  if (effectiveMode != _EditorMode.preview) toolbar,
                ],
              ),
            ),
            hairline,
            Expanded(child: body),
          ],
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (focusMode) {
          _toggleFocusMode();
        } else {
          unawaited(_handleBack());
        }
      },
      child: CallbackShortcuts(bindings: _shortcuts, child: scaffold),
    );
  }
}

class _ToolbarGap extends StatelessWidget {
  const _ToolbarGap();

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 18,
    child: VerticalDivider(
      width: Insets.md,
      color: AppColors.of(context).border,
    ),
  );
}

class _SaveIndicator extends StatelessWidget {
  const _SaveIndicator({required this.state});

  final _SaveState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final (IconData icon, String label, Color color) = switch (state) {
      _SaveState.saved => (
        Icons.cloud_done_outlined,
        'Saved',
        colors.faintText,
      ),
      _SaveState.dirty => (Icons.edit_outlined, 'Unsaved', colors.mutedText),
      _SaveState.saving => (Icons.sync, 'Saving…', colors.mutedText),
      _SaveState.failed => (Icons.error_outline, 'Not saved', colors.danger),
    };
    final showLabel = Breakpoints.isMedium(context);
    return Tooltip(
      message: label,
      child: Row(
        key: const Key('note-save-state'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          if (showLabel) ...[
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(color: color),
            ),
          ],
        ],
      ),
    );
  }
}
