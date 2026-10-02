import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/widgets/error_message.dart';
import '../../../core/widgets/note_markdown.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/state_views.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/models.dart';
import '../application/markdown_editing.dart';
import '../application/note_image_picker.dart';
import 'widgets/markdown_toolbar.dart';

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
      final saved = await ref
          .read(noteRepositoryProvider)
          .update(note.copyWith(title: title, contentMd: content));
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
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit note')),
        body: const Center(child: CircularProgressIndicator()),
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

    final wide = Breakpoints.isExpanded(context);
    final mode = _mode ?? (wide ? _EditorMode.split : _EditorMode.write);
    final effectiveMode = !wide && mode == _EditorMode.split
        ? _EditorMode.write
        : mode;

    final editor = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MarkdownToolbar(
          controller: _content,
          focusNode: _contentFocus,
          onInsertLink: _insertLink,
          onInsertImage: _insertImage,
          imageBusy: _imageBusy,
        ),
        const Divider(height: 1),
        Expanded(
          child: TextField(
            key: const Key('note-content'),
            controller: _content,
            focusNode: _contentFocus,
            expands: true,
            maxLines: null,
            minLines: null,
            keyboardType: TextInputType.multiline,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(fontFamily: 'monospace', height: 1.45),
            decoration: const InputDecoration(
              hintText: 'Write in Markdown… e.g. ## Heading, **bold**, - list',
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(16),
            ),
          ),
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
              padding: const EdgeInsets.all(16),
              child: NoteMarkdown(data: _content.text),
            ),
    );

    final body = switch (effectiveMode) {
      _EditorMode.write => editor,
      _EditorMode.preview => preview,
      _EditorMode.split => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: editor),
          const VerticalDivider(width: 1),
          Expanded(child: preview),
        ],
      ),
    };

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_handleBack());
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
              unawaited(_save(showConfirmation: true)),
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
              unawaited(_save(showConfirmation: true)),
          const SingleActivator(LogicalKeyboardKey.keyB, control: true): () =>
              _wrap('**', 'bold'),
          const SingleActivator(LogicalKeyboardKey.keyI, control: true): () =>
              _wrap('_', 'italic'),
        },
        child: Scaffold(
          appBar: AppBar(
            leading: BackButton(onPressed: () => unawaited(_handleBack())),
            title: const Text('Edit note'),
            actions: [
              _SaveIndicator(state: _saveState),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: SegmentedButton<_EditorMode>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
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
                tooltip: 'Save (Ctrl+S)',
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: TextField(
                  key: const Key('note-title'),
                  controller: _title,
                  style: Theme.of(context).textTheme.headlineSmall,
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
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
  }
}

class _SaveIndicator extends StatelessWidget {
  const _SaveIndicator({required this.state});

  final _SaveState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (IconData icon, String label, Color color) = switch (state) {
      _SaveState.saved => (
        Icons.cloud_done_outlined,
        'Saved',
        theme.colorScheme.onSurfaceVariant,
      ),
      _SaveState.dirty => (
        Icons.edit_outlined,
        'Unsaved',
        theme.colorScheme.onSurfaceVariant,
      ),
      _SaveState.saving => (
        Icons.sync,
        'Saving…',
        theme.colorScheme.onSurfaceVariant,
      ),
      _SaveState.failed => (
        Icons.error_outline,
        'Not saved',
        theme.colorScheme.error,
      ),
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
