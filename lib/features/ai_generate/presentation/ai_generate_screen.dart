import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../ai/ai_capabilities.dart';
import '../../../ai/ai_providers.dart';
import '../../../ai/ai_readiness.dart';
import '../../../ai/ai_service.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../../core/widgets/design_system.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/models.dart';
import '../../quizzes/domain/question_rules.dart';
import '../../quizzes/widgets/question_list_editor.dart';
import '../../quizzes/widgets/quiz_format.dart'
    show errorText, plural, questionTypeIcon, questionTypeLabel, showSnack;
import '../domain/generation_sources.dart';
import '../widgets/ai_error_card.dart';
import '../widgets/attachment_picker.dart';
import '../widgets/note_draft_editor.dart';
import '../widgets/note_picker.dart';

/// What to generate.
enum AiGenerateKind { quiz, note }

enum _Stage { form, generating, preview }

enum NoteStyle {
  summary('Summary', 'Write a concise summary of the key points.'),
  studyNotes(
    'Study notes',
    'Write detailed study notes with headings, key terms and examples.',
  ),
  outline('Outline', 'Write a structured outline with nested bullet points.');

  const NoteStyle(this.label, this.instruction);
  final String label;
  final String instruction;
}

enum NoteLength {
  short('Short', 'Keep it short (about 200-400 words).'),
  medium('Medium', 'Aim for about 500-900 words.'),
  long('Long', 'Be thorough (1000+ words).');

  const NoteLength(this.label, this.instruction);
  final String label;
  final String instruction;
}

/// Two-column layout from this body width.
const double _twoColumnWidth = 900;

/// AI generation: sources (text, notes, files, YouTube) + options →
/// progress (cancellable) → editable preview → save as a quiz (subject- or
/// note-level) or a note. Shows only a "Set up AI" state until a provider
/// is configured.
class AiGenerateScreen extends ConsumerStatefulWidget {
  const AiGenerateScreen({
    super.key,
    required this.kind,
    this.subjectId,
    this.noteId,
  });

  final AiGenerateKind kind;

  /// Target subject (pre-selected); may be null to let the user pick.
  final String? subjectId;

  /// Attach a generated quiz to this note; the note is preselected as a
  /// source.
  final String? noteId;

  @override
  ConsumerState<AiGenerateScreen> createState() => _AiGenerateScreenState();
}

class _AiGenerateScreenState extends ConsumerState<AiGenerateScreen> {
  // Sources.
  final _text = TextEditingController();
  final _youtube = TextEditingController();
  List<Note> _notes = [];
  List<Attachment> _files = [];

  // Options.
  final _language = TextEditingController();
  final _instructions = TextEditingController();
  int _count = 10;
  Set<QuestionType> _types = {...QuestionType.values};
  Difficulty _difficulty = Difficulty.medium;
  NoteStyle _noteStyle = NoteStyle.studyNotes;
  NoteLength _noteLength = NoteLength.medium;
  String? _pickedSubjectId;
  Note? _note;
  bool _notePreselected = false;

  // Validation (shown after the first Generate).
  bool _validated = false;

  // Generation.
  _Stage _stage = _Stage.form;
  int _generation = 0;
  bool _preparing = false;
  Object? _error;
  AiSelection? _used;
  QuizGenerationRequest? _quizRequest;
  SourceSelection _usedSources = const SourceSelection();

  // Preview.
  final _draftTitle = TextEditingController();
  final _draftDescription = TextEditingController();
  final _noteBody = TextEditingController();
  List<Question> _questions = [];
  final Set<String> _regenerating = {};
  bool _draftDirty = false;
  bool _showIssues = false;
  String? _draftTitleError;
  bool _saving = false;

  bool get _isQuiz => widget.kind == AiGenerateKind.quiz;

  @override
  void initState() {
    super.initState();
    final noteId = widget.noteId;
    if (noteId != null) {
      ref.listenManual<AsyncValue<Note?>>(noteProvider(noteId), (_, next) {
        final note = next.value;
        if (note == null) return;
        _note = note;
        if (!_notePreselected) {
          _notePreselected = true;
          if (!_notes.any((n) => n.id == note.id)) _notes = [note, ..._notes];
        }
        if (mounted) setState(() {});
      }, fireImmediately: true);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _text,
      _youtube,
      _language,
      _instructions,
      _draftTitle,
      _draftDescription,
      _noteBody,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  AiReadiness? get _readiness => ref.read(aiReadinessProvider).value;

  AiCapabilities get _caps =>
      _readiness?.capabilities ?? AiCapabilities.textOnly;

  AiSelection? _selectionOf(AiReadiness? r) =>
      r != null && r.isConfigured && r.providerId != null && r.model != null
      ? AiSelection(providerId: r.providerId!, model: r.model!)
      : null;

  void _openSettings() => context.push(AppRoutes.settings);

  String? get _subjectId =>
      _note?.subjectId ?? widget.subjectId ?? _pickedSubjectId;

  // ---------------------------------------------------------------------------
  // Sources & validation
  // ---------------------------------------------------------------------------

  String? get _youtubeError {
    if (!_caps.youtube) return null;
    try {
      parseYoutubeInput(_youtube.text);
      return null;
    } on FormatException catch (e) {
      return e.message;
    }
  }

  SourceSelection get _sources {
    String? youtube;
    if (_caps.youtube && _youtubeError == null) {
      youtube = parseYoutubeInput(_youtube.text);
    }
    return SourceSelection(
      text: _text.text,
      notes: _notes,
      files: _files,
      youtubeUrl: youtube,
    );
  }

  List<Attachment> get _unsupportedFiles => [
    for (final a in _files)
      if (fileKindProblem(a.kind, _caps) != null) a,
  ];

  String? get _sourceError {
    final s = _sources;
    if (s.isEmpty) {
      return 'Add some text, a note, a file or a YouTube link to generate '
          'from.';
    }
    final bad = _unsupportedFiles;
    if (bad.isNotEmpty) {
      return "Remove files this model can't read: "
          '${bad.map((a) => a.name).join(', ')}.';
    }
    final sel = _selectionOf(_readiness);
    final limit = sel == null ? null : requestFileLimit(sel.providerId);
    final total = binaryFileBytes(_files);
    if (limit != null && total > limit) {
      return 'The files total ${formatFileSize(total)}; '
          '${sel!.providerId.displayName} accepts up to '
          '${formatFileSize(limit)} per request. Remove some files.';
    }
    return null;
  }

  String? get _subjectError =>
      _subjectId == null ? 'Choose where to save the result.' : null;

  String? get _typesError =>
      _isQuiz && _types.isEmpty ? 'Pick at least one question type.' : null;

  bool get _inputValid =>
      _youtubeError == null &&
      _sourceError == null &&
      _subjectError == null &&
      _typesError == null;

  Future<void> _addNotes() async {
    final picked = await showNotePicker(context, selected: _notes);
    if (picked != null && mounted) setState(() => _notes = picked);
  }

  Future<void> _addFiles() async {
    final subjectId = _subjectId;
    if (subjectId == null) return;
    final picked = await showAttachmentPicker(
      context,
      subjectId: subjectId,
      capabilities: _caps,
      selected: _files,
    );
    if (picked != null && mounted) setState(() => _files = picked);
  }

  // ---------------------------------------------------------------------------
  // Generation
  // ---------------------------------------------------------------------------

  String? _blankToNull(String s) => s.trim().isEmpty ? null : s.trim();

  String? get _topic {
    if (_note != null) return _note!.title;
    final id = _subjectId;
    if (id == null) return null;
    final subject =
        ref.read(subjectProvider(id)).value ??
        ref.read(subjectsProvider).value?.where((s) => s.id == id).firstOrNull;
    return subject?.title;
  }

  String? get _noteInstructions => [
    _noteStyle.instruction,
    _noteLength.instruction,
    ?_blankToNull(_instructions.text),
  ].join('\n');

  Future<void> _generate() async {
    setState(() => _validated = true);
    if (!_inputValid) return;
    final sel = _selectionOf(_readiness);
    if (sel == null) return;
    FocusScope.of(context).unfocus();
    final gen = ++_generation;
    final selection = _sources;
    setState(() {
      _stage = _Stage.generating;
      _preparing = selection.files.isNotEmpty;
      _error = null;
    });
    final ai = ref.read(aiServiceProvider);
    try {
      final sources = await selection.toAiSources(
        (a) => ref.read(attachmentRepositoryProvider).getBytes(a),
      );
      if (gen != _generation || !mounted) return;
      setState(() => _preparing = false);
      if (_isQuiz) {
        final request = QuizGenerationRequest(
          sources: sources,
          questionCount: _count,
          questionTypes: {..._types},
          difficulty: _difficulty,
          language: _blankToNull(_language.text),
          extraInstructions: _blankToNull(_instructions.text),
          topic: _topic,
          providerId: sel.providerId,
          model: sel.model,
        );
        final draft = await ai.generateQuiz(request);
        if (gen != _generation || !mounted) return;
        final newId = ref.read(idGeneratorProvider);
        setState(() {
          _used = sel;
          _quizRequest = request;
          _usedSources = selection;
          _draftTitle.text = draft.title;
          _draftDescription.text = draft.description ?? '';
          _questions = draft.toQuestions(newId);
          _resetPreviewState();
        });
      } else {
        final request = NoteGenerationRequest(
          sources: sources,
          language: _blankToNull(_language.text),
          extraInstructions: _noteInstructions,
          topic: _topic,
          providerId: sel.providerId,
          model: sel.model,
        );
        final draft = await ai.generateNote(request);
        if (gen != _generation || !mounted) return;
        setState(() {
          _used = sel;
          _usedSources = selection;
          _draftTitle.text = draft.title;
          _noteBody.text = draft.contentMarkdown;
          _resetPreviewState();
        });
      }
    } on Object catch (e) {
      if (gen != _generation || !mounted) return;
      setState(() {
        _error = e;
        _preparing = false;
        _stage = _Stage.form;
      });
    }
  }

  void _resetPreviewState() {
    _regenerating.clear();
    _draftDirty = false;
    _showIssues = true; // AI drafts are validated, but highlight anything odd
    _draftTitleError = null;
    _stage = _Stage.preview;
  }

  void _cancel() {
    setState(() {
      _generation++;
      _preparing = false;
      _stage = _Stage.form;
    });
  }

  Future<bool> _confirmDiscard({
    required String title,
    required String confirm,
  }) async {
    if (!_draftDirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: const Text('Your edits to the draft will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep draft'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirm),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _regenerateAll() async {
    if (!await _confirmDiscard(
      title: 'Regenerate the draft?',
      confirm: 'Regenerate',
    )) {
      return;
    }
    if (mounted) await _generate();
  }

  Future<void> _backToOptions() async {
    if (!await _confirmDiscard(
      title: 'Discard the draft?',
      confirm: 'Discard',
    )) {
      return;
    }
    if (mounted) setState(() => _stage = _Stage.form);
  }

  Future<void> _regenerateQuestion(Question q) async {
    final base = _quizRequest;
    if (base == null) return;
    setState(() => _regenerating.add(q.id));
    try {
      final existing = _questions.map((x) => '- ${x.prompt}').join('\n');
      final draft = await ref
          .read(aiServiceProvider)
          .generateQuiz(
            base.copyWith(
              questionCount: 1,
              questionTypes: {q.type},
              extraInstructions: [
                ?base.extraInstructions,
                'Write exactly one new question. It must be different from '
                    'these existing questions:\n$existing',
              ].join('\n\n'),
            ),
          );
      if (draft.questions.isEmpty) {
        throw const AiException(
          'The AI returned no question.',
          kind: AiErrorKind.invalidOutput,
        );
      }
      if (!mounted) return;
      final replacement = draft.questions.first.toQuestion(
        ref.read(idGeneratorProvider)(),
      );
      setState(() {
        final i = _questions.indexWhere((x) => x.id == q.id);
        if (i >= 0) {
          _questions = [..._questions]..[i] = replacement;
          _draftDirty = true;
        }
      });
    } on Object catch (e) {
      if (mounted) {
        final info = describeAiError(e);
        showSnack(context, '${info.title}: ${info.message}');
      }
    } finally {
      if (mounted) setState(() => _regenerating.remove(q.id));
    }
  }

  // ---------------------------------------------------------------------------
  // Save
  // ---------------------------------------------------------------------------

  Future<void> _save() async {
    final subjectId = _subjectId;
    final title = _draftTitle.text.trim();
    if (subjectId == null) return;
    if (_isQuiz) {
      final invalid = _questions.where((q) => validateQuestion(q).isNotEmpty);
      setState(() {
        _draftTitleError = title.isEmpty ? 'Give the quiz a title.' : null;
        _showIssues = true;
      });
      if (title.isEmpty) return;
      if (_questions.isEmpty) {
        showSnack(context, 'Add at least one question.');
        return;
      }
      if (invalid.isNotEmpty) {
        showSnack(
          context,
          'Fix ${plural(invalid.length, 'question')} marked in red first.',
        );
        return;
      }
    } else {
      setState(() {
        _draftTitleError = title.isEmpty ? 'Give the note a title.' : null;
      });
      if (title.isEmpty) return;
    }

    setState(() => _saving = true);
    try {
      final String location;
      if (_isQuiz) {
        final quiz = await ref
            .read(quizRepositoryProvider)
            .create(
              subjectId: subjectId,
              noteId: widget.noteId,
              title: title,
              description: _blankToNull(_draftDescription.text),
              questions: [for (final q in _questions) normalizeQuestion(q)],
              source: _usedSources.toQuizSource(_used),
            );
        location = AppRoutes.quiz(quiz.id);
      } else {
        final note = await ref
            .read(noteRepositoryProvider)
            .create(
              subjectId: subjectId,
              title: title,
              contentMd: _noteBody.text,
            );
        location = AppRoutes.noteEdit(note.id);
      }
      if (!mounted) return;
      setState(() {
        _draftDirty = false;
        _stage = _Stage.form;
      });
      showSnack(context, _isQuiz ? 'Quiz saved' : 'Note saved');
      context.pushReplacement(location);
    } on Object catch (e) {
      if (mounted) showSnack(context, errorText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  Future<void> _onPopBlocked() async {
    if (_stage == _Stage.generating) {
      _cancel();
      return;
    }
    if (_stage == _Stage.preview &&
        await _confirmDiscard(
          title: 'Discard the draft?',
          confirm: 'Discard',
        )) {
      if (!mounted) return;
      setState(() {
        _draftDirty = false;
        _stage = _Stage.form;
      });
      if (context.canPop()) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final readiness = ref.watch(aiReadinessProvider);
    final r = readiness.value;
    final title = switch ((_isQuiz, _stage)) {
      (true, _Stage.preview) => 'Review quiz',
      (false, _Stage.preview) => 'Review note',
      (true, _) => 'Generate quiz with AI',
      (false, _) => 'Generate note with AI',
    };
    final Widget body;
    if (_stage == _Stage.form && r == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_stage == _Stage.form && !r!.isConfigured) {
      body = _notReady(r);
    } else {
      body = switch (_stage) {
        _Stage.form => _form(context, r!),
        _Stage.generating => _progress(context),
        _Stage.preview => _isQuiz ? _quizPreview(context) : _notePreview(),
      };
    }
    return PopScope(
      canPop: _stage == _Stage.form,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onPopBlocked();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: body,
        bottomNavigationBar: _stage == _Stage.preview
            ? _previewActions(context)
            : null,
      ),
    );
  }

  // --- Not ready --------------------------------------------------------------

  Widget _notReady(AiReadiness r) => EmptyState(
    key: const Key('ai-not-ready'),
    icon: Icons.auto_awesome_outlined,
    title: 'Set up AI to generate',
    message: [
      ?r.reason,
      'AI uses your own API key (Gemini, OpenAI, Anthropic or an '
          'OpenAI-compatible endpoint). Keys stay on this device.',
    ].join('\n\n'),
    action: FilledButton(
      key: const Key('ai-open-settings'),
      onPressed: _openSettings,
      child: const Text('Open Settings'),
    ),
  );

  // --- Form -------------------------------------------------------------------

  Widget _form(BuildContext context, AiReadiness r) {
    final error = _error == null
        ? null
        : AiErrorCard(
            error: _error!,
            onOpenSettings: _openSettings,
            onRetry: _generate,
            onDismiss: () => setState(() => _error = null),
          );
    final needsSubjectPicker =
        widget.noteId == null && widget.subjectId == null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _twoColumnWidth;
        final sources = _sourcesPanel(context, r);
        Widget side() => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _targetPanel(context),
            Gaps.h16,
            _optionsPanel(context),
            Gaps.h16,
            _generateBar(context, r),
          ],
        );
        return SingleChildScrollView(
          padding: wide ? Insets.pageWide : Insets.page,
          child: ContentContainer(
            maxWidth: wide ? ContentWidth.wide : ContentWidth.form,
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _providerHeader(context, r),
                Gaps.h16,
                if (error != null) ...[error, Gaps.h16],
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: sources),
                      Gaps.w24,
                      SizedBox(width: 380, child: side()),
                    ],
                  )
                else ...[
                  // The library of files needs a subject: ask for it first.
                  if (needsSubjectPicker) ...[_targetPanel(context), Gaps.h16],
                  sources,
                  Gaps.h16,
                  if (!needsSubjectPicker) ...[_targetPanel(context), Gaps.h16],
                  _optionsPanel(context),
                  Gaps.h16,
                  _generateBar(context, r),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _providerHeader(BuildContext context, AiReadiness r) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Row(
      children: [
        Icon(Icons.auto_awesome_outlined, size: 16, color: colors.mutedText),
        Gaps.w8,
        Flexible(
          child: Text(
            '${r.providerId?.displayName ?? 'AI'} · ${r.model ?? ''}',
            key: const Key('ai-provider'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.mutedText,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Gaps.w4,
        TextButton(
          key: const Key('ai-change-provider'),
          onPressed: _openSettings,
          child: const Text('Change'),
        ),
      ],
    );
  }

  Widget _sourcesPanel(BuildContext context, AiReadiness r) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final caps = r.capabilities;
    final sourceError = _validated ? _sourceError : null;
    Widget muted(String text, {Key? key}) => Text(
      text,
      key: key,
      style: theme.textTheme.bodySmall?.copyWith(color: colors.mutedText),
    );

    final subjectId = _subjectId;
    final blocks = <Widget>[
      _SourceBlock(
        icon: Icons.short_text,
        title: 'Text',
        child: TextField(
          key: const Key('ai-context'),
          controller: _text,
          minLines: 4,
          maxLines: 14,
          decoration: const InputDecoration(
            hintText: 'Paste notes, an article, a transcript…',
          ),
          onChanged: (_) => setState(() {}),
        ),
      ),
      _SourceBlock(
        icon: Icons.description_outlined,
        title: 'Notes',
        trailing: TextButton.icon(
          key: const Key('ai-add-notes'),
          onPressed: _addNotes,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add notes'),
        ),
        child: _notes.isEmpty
            ? muted('Use any of your notes, or notes shared with you.')
            : Wrap(
                spacing: Insets.sm,
                runSpacing: Insets.sm,
                children: [
                  for (final n in _notes)
                    InputChip(
                      key: ValueKey('note-chip-${n.id}'),
                      avatar: const Icon(Icons.description_outlined, size: 16),
                      label: Text(
                        n.title.trim().isEmpty ? 'Untitled' : n.title,
                        overflow: TextOverflow.ellipsis,
                      ),
                      deleteButtonTooltipMessage: 'Remove',
                      onDeleted: () => setState(
                        () => _notes = [
                          for (final x in _notes)
                            if (x.id != n.id) x,
                        ],
                      ),
                    ),
                ],
              ),
      ),
      _SourceBlock(
        icon: Icons.attach_file,
        title: 'Files',
        trailing: TextButton.icon(
          key: const Key('ai-add-files'),
          onPressed: subjectId == null ? null : _addFiles,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add files'),
        ),
        child: subjectId == null
            ? muted(
                'Choose where to save the result first — files come from '
                "that subject's library.",
                key: const Key('ai-files-need-subject'),
              )
            : _files.isEmpty
            ? muted(
                '${uploadKindsLabel(caps)} from the subject library, or '
                'upload new ones.',
                key: const Key('ai-files-hint'),
              )
            : Wrap(
                spacing: Insets.sm,
                runSpacing: Insets.sm,
                children: [for (final a in _files) _fileChip(context, a)],
              ),
      ),
      if (caps.youtube)
        _SourceBlock(
          icon: Icons.smart_display_outlined,
          title: 'YouTube',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('ai-youtube'),
                controller: _youtube,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  hintText: 'https://www.youtube.com/watch?v=…',
                  errorText: _youtubeError,
                  helperText: caps.youtubeNative
                      ? '${r.providerId?.displayName ?? 'The model'} watches '
                            'the video directly.'
                      : "Uses the video's captions.",
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (kIsWeb &&
                  !caps.youtubeNative &&
                  _youtube.text.trim().isNotEmpty) ...[
                Gaps.h8,
                const InfoBanner(
                  kind: InfoBannerKind.warning,
                  message:
                      'In the browser, YouTube usually blocks caption '
                      'downloads, so this model may not be able to use the '
                      'video. Switch to Gemini in Settings, or paste the '
                      'transcript as text.',
                ),
              ],
            ],
          ),
        )
      else
        _SourceBlock(
          icon: Icons.smart_display_outlined,
          title: 'YouTube',
          child: muted(
            "This model can't use YouTube videos here. Gemini can watch "
            'them directly — switch in Settings.',
            key: const Key('ai-youtube-unavailable'),
          ),
        ),
    ];

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(Insets.lg, Insets.md, Insets.lg, 0),
            child: SectionHeader(
              title: 'Sources',
              subtitle: 'Combine any of these.',
              padding: EdgeInsets.zero,
            ),
          ),
          if (sourceError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.lg,
                Insets.sm,
                Insets.lg,
                0,
              ),
              child: Text(
                sourceError,
                key: const Key('ai-source-error'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          for (final (i, b) in blocks.indexed) ...[
            if (i > 0) Divider(height: 1, color: colors.hairline),
            b,
          ],
        ],
      ),
    );
  }

  Widget _fileChip(BuildContext context, Attachment a) {
    final problem = fileKindProblem(a.kind, _caps);
    final me = ref.watch(currentUserIdProvider);
    final theme = Theme.of(context);
    final chip = InputChip(
      key: ValueKey('file-chip-${a.id}'),
      avatar: Icon(
        problem == null ? attachmentKindIcon(a.kind) : Icons.block,
        size: 16,
        color: problem == null ? null : theme.colorScheme.error,
      ),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: Text(a.name, overflow: TextOverflow.ellipsis)),
          Gaps.w4,
          Text(
            formatFileSize(a.sizeBytes),
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.of(context).faintText,
            ),
          ),
          if (a.isOwnedBy(me)) ...[Gaps.w4, UploadStatusPill(attachment: a)],
        ],
      ),
      deleteButtonTooltipMessage: 'Remove',
      onDeleted: () => setState(
        () => _files = [
          for (final x in _files)
            if (x.id != a.id) x,
        ],
      ),
    );
    return problem == null ? chip : Tooltip(message: problem, child: chip);
  }

  Widget _targetPanel(BuildContext context) {
    final theme = Theme.of(context);
    Widget panel(Widget child) => _Panel(title: 'Save to', child: child);
    if (widget.noteId != null) {
      final note = _note;
      return panel(
        Text(
          note == null
              ? 'Loading note…'
              : _isQuiz
              ? 'Quiz for the note "${note.title}"'
              : 'New note in the same subject as "${note.title}"',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }
    if (widget.subjectId != null) {
      final subject = ref.watch(subjectProvider(widget.subjectId!)).value;
      return panel(
        Row(
          children: [
            SubjectColorDot(color: subject?.color),
            Gaps.w8,
            Expanded(
              child: Text(
                subject == null ? 'Loading subject…' : subject.title,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      );
    }
    final subjects = ref.watch(subjectsProvider);
    return panel(switch (subjects) {
      AsyncValue(:final value?) when value.isEmpty => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('You have no subjects yet. Create one first.'),
          TextButton(
            onPressed: () => context.go(AppRoutes.subjects),
            child: const Text('Go to subjects'),
          ),
        ],
      ),
      AsyncValue(:final value?) => DropdownButtonFormField<String>(
        key: const Key('ai-subject'),
        initialValue: _pickedSubjectId,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Subject',
          isDense: true,
          errorText: _validated ? _subjectError : null,
        ),
        items: [
          for (final s in value)
            DropdownMenuItem(
              value: s.id,
              child: Row(
                children: [
                  SubjectColorDot(color: s.color),
                  Gaps.w8,
                  Expanded(
                    child: Text(s.title, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
        ],
        onChanged: (id) => setState(() {
          // Files belong to the previous subject's library.
          if (id != _pickedSubjectId) _files = [];
          _pickedSubjectId = id;
        }),
      ),
      AsyncValue(:final error?) => Text(errorText(error)),
      _ => const LinearProgressIndicator(),
    });
  }

  Widget _optionsPanel(BuildContext context) {
    final theme = Theme.of(context);
    final label = theme.textTheme.labelLarge;
    return _Panel(
      title: 'Options',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_isQuiz) ...[
            Row(
              children: [
                Text('Questions', style: label),
                const Spacer(),
                Text('$_count', key: const Key('ai-count'), style: label),
              ],
            ),
            Slider(
              value: _count.toDouble(),
              min: 1,
              max: 50,
              divisions: 49,
              label: '$_count',
              onChanged: (x) => setState(() => _count = x.round()),
            ),
            Text('Question types', style: label),
            Gaps.h8,
            Wrap(
              spacing: Insets.sm,
              runSpacing: Insets.sm,
              children: [
                for (final t in QuestionType.values)
                  FilterChip(
                    avatar: Icon(questionTypeIcon(t), size: 16),
                    label: Text(questionTypeLabel(t)),
                    selected: _types.contains(t),
                    showCheckmark: false,
                    onSelected: (on) => setState(() {
                      _types = on ? ({..._types, t}) : ({..._types}..remove(t));
                    }),
                  ),
              ],
            ),
            if (_validated && _typesError != null)
              Padding(
                padding: const EdgeInsets.only(top: Insets.xs),
                child: Text(
                  _typesError!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            Gaps.h16,
            Text('Difficulty', style: label),
            Gaps.h8,
            SegmentedButton<Difficulty>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: Difficulty.easy, label: Text('Easy')),
                ButtonSegment(value: Difficulty.medium, label: Text('Medium')),
                ButtonSegment(value: Difficulty.hard, label: Text('Hard')),
              ],
              selected: {_difficulty},
              onSelectionChanged: (s) => setState(() => _difficulty = s.first),
            ),
          ] else ...[
            Text('Style', style: label),
            Gaps.h8,
            SegmentedButton<NoteStyle>(
              showSelectedIcon: false,
              segments: [
                for (final s in NoteStyle.values)
                  ButtonSegment(value: s, label: Text(s.label)),
              ],
              selected: {_noteStyle},
              onSelectionChanged: (s) => setState(() => _noteStyle = s.first),
            ),
            Gaps.h16,
            Text('Length', style: label),
            Gaps.h8,
            SegmentedButton<NoteLength>(
              showSelectedIcon: false,
              segments: [
                for (final l in NoteLength.values)
                  ButtonSegment(value: l, label: Text(l.label)),
              ],
              selected: {_noteLength},
              onSelectionChanged: (s) => setState(() => _noteLength = s.first),
            ),
          ],
          Gaps.h16,
          TextField(
            key: const Key('ai-language'),
            controller: _language,
            decoration: const InputDecoration(
              labelText: 'Language',
              hintText: 'Same as the sources',
              isDense: true,
            ),
          ),
          Gaps.h12,
          TextField(
            key: const Key('ai-instructions'),
            controller: _instructions,
            minLines: 1,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: 'Focus (optional)',
              hintText: _isQuiz
                  ? 'e.g. Dates and definitions'
                  : 'e.g. Key terms and formulas',
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _generateBar(BuildContext context, AiReadiness r) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final s = _sources;
    final sel = _selectionOf(r);
    final fileBytes = binaryFileBytes(_files);
    final limit = sel == null ? null : requestFileLimit(sel.providerId);
    final summary = [
      s.count == 0 ? 'No sources yet' : plural(s.count, 'source'),
      if (_files.isNotEmpty && fileBytes > 0)
        '${formatFileSize(fileBytes)} of files'
            '${limit == null ? '' : ' (max ${formatFileSize(limit)} per request)'}',
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          summary,
          key: const Key('ai-source-summary'),
          style: theme.textTheme.bodySmall?.copyWith(color: colors.mutedText),
        ),
        Gaps.h8,
        FilledButton.icon(
          key: const Key('ai-generate'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
          onPressed: _generate,
          icon: const Icon(Icons.auto_awesome, size: 18),
          label: Text(_isQuiz ? 'Generate quiz' : 'Generate note'),
        ),
      ],
    );
  }

  // --- Progress ----------------------------------------------------------------

  Widget _progress(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final sel = _selectionOf(_readiness);
    final s = _sources;
    final usesCaptions = s.youtubeUrl != null && !_caps.youtubeNative;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Insets.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox.square(
                dimension: 32,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              Gaps.h24,
              Text(
                _isQuiz ? 'Generating your quiz…' : 'Writing your note…',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              Gaps.h8,
              Text(
                [
                  if (_preparing) 'Preparing files…',
                  if (sel != null)
                    'Using ${sel.providerId.displayName} · ${sel.model}.',
                  if (usesCaptions) "Fetching the video's captions first.",
                  'This can take up to a couple of minutes.',
                ].join(' '),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.mutedText,
                ),
                textAlign: TextAlign.center,
              ),
              Gaps.h24,
              OutlinedButton.icon(
                key: const Key('ai-cancel'),
                onPressed: _cancel,
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Preview -----------------------------------------------------------------

  Widget _previewInfo(BuildContext context) {
    final used = _used;
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.lg),
      child: InfoBanner(
        icon: Icons.auto_awesome_outlined,
        message:
            'Review and edit the draft before saving. AI can make mistakes.'
            '${used == null ? '' : ' Generated by ${used.providerId.displayName} · ${used.model}.'}',
      ),
    );
  }

  Widget _quizPreview(BuildContext context) {
    final theme = Theme.of(context);
    final header = Padding(
      padding: const EdgeInsets.only(bottom: Insets.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _previewInfo(context),
          TextField(
            key: const Key('draft-title'),
            controller: _draftTitle,
            style: theme.textTheme.titleLarge,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Title',
              errorText: _draftTitleError,
            ),
            onChanged: (_) => setState(() {
              _draftDirty = true;
              _draftTitleError = null;
            }),
          ),
          Gaps.h12,
          TextField(
            controller: _draftDescription,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
            ),
            onChanged: (_) => _draftDirty = true,
          ),
          Gaps.h8,
          SectionHeader(title: 'Questions', count: _questions.length),
        ],
      ),
    );
    return MaxWidth(
      maxWidth: ContentWidth.readable,
      child: QuestionListEditor(
        questions: _questions,
        newId: ref.read(idGeneratorProvider),
        header: header,
        showIssues: _showIssues,
        busyIds: _regenerating,
        onRegenerate: _regenerateQuestion,
        onChanged: (list) => setState(() {
          _questions = list;
          _draftDirty = true;
        }),
        padding: const EdgeInsets.fromLTRB(
          Insets.lg,
          Insets.lg,
          Insets.lg,
          Insets.xl,
        ),
      ),
    );
  }

  Widget _notePreview() => MaxWidth(
    maxWidth: 1400,
    child: NoteDraftEditor(
      title: _draftTitle,
      body: _noteBody,
      titleError: _draftTitleError,
      header: _previewInfo(context),
      onChanged: () {
        _draftDirty = true;
        if (_draftTitleError != null) {
          setState(() => _draftTitleError = null);
        }
      },
    ),
  );

  Widget _previewActions(BuildContext context) {
    final busy = _saving || _regenerating.isNotEmpty;
    final colors = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: colors.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.lg,
            vertical: Insets.sm + 2,
          ),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: busy ? null : _backToOptions,
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Options'),
              ),
              const Spacer(),
              Flexible(
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: Insets.sm,
                  runSpacing: Insets.sm,
                  children: [
                    OutlinedButton.icon(
                      key: const Key('ai-regenerate'),
                      onPressed: busy ? null : _regenerateAll,
                      icon: const Icon(Icons.autorenew, size: 18),
                      label: const Text('Regenerate'),
                    ),
                    FilledButton.icon(
                      key: const Key('ai-save'),
                      onPressed: busy ? null : _save,
                      icon: _saving
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check, size: 18),
                      label: Text(_isQuiz ? 'Save quiz' : 'Save note'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Quiet titled group in an outlined card.
class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: title,
          padding: const EdgeInsets.only(bottom: Insets.md),
        ),
        child,
      ],
    ),
  );
}

/// One kind of source inside the Sources card.
class _SourceBlock extends StatelessWidget {
  const _SourceBlock({
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.lg,
        Insets.md,
        Insets.lg,
        Insets.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Row(
              children: [
                Icon(icon, size: 18, color: colors.mutedText),
                Gaps.w8,
                Expanded(child: Text(title, style: theme.textTheme.labelLarge)),
                ?trailing,
              ],
            ),
          ),
          Gaps.h4,
          child,
        ],
      ),
    );
  }
}
