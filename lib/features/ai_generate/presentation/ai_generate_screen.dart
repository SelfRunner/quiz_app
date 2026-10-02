import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../ai/ai_providers.dart';
import '../../../ai/ai_service.dart';
import '../../../ai/youtube_url.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/models.dart';
import '../../quizzes/domain/question_rules.dart';
import '../../quizzes/widgets/question_list_editor.dart';
import '../../quizzes/widgets/quiz_format.dart';
import '../widgets/ai_error_card.dart';
import '../widgets/note_draft_editor.dart';

/// What to generate.
enum AiGenerateKind { quiz, note }

enum _Stage { form, generating, preview }

/// Max characters of pasted context kept in `QuizSource.contextText`.
const int _maxStoredContext = 20000;

/// AI generation: inputs → progress (cancellable) → editable preview → save
/// as a quiz (subject- or note-level) or a note.
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

  /// Attach a generated quiz to this note.
  final String? noteId;

  @override
  ConsumerState<AiGenerateScreen> createState() => _AiGenerateScreenState();
}

class _AiGenerateScreenState extends ConsumerState<AiGenerateScreen> {
  // Inputs.
  final _context = TextEditingController();
  final _youtube = TextEditingController();
  final _topic = TextEditingController();
  final _language = TextEditingController();
  final _instructions = TextEditingController();
  int _count = 10;
  Set<QuestionType> _types = {...QuestionType.values};
  Difficulty _difficulty = Difficulty.medium;
  String? _pickedSubjectId;
  bool _prefilled = false;
  Note? _note;

  // Validation (shown after the first Generate).
  bool _validated = false;

  // Provider selection.
  AiSelection? _selection;
  Object? _selectionError;
  bool _selectionLoading = true;

  // Generation.
  _Stage _stage = _Stage.form;
  int _generation = 0;
  Object? _error;
  AiSelection? _used;
  QuizGenerationRequest? _quizRequest;
  String? _usedContext;
  String? _usedYoutube;

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
        if (!_prefilled) {
          _prefilled = true;
          if (_context.text.isEmpty) _context.text = note.contentMd;
        }
        if (mounted) setState(() {});
      }, fireImmediately: true);
    }
    _resolveSelection();
  }

  @override
  void dispose() {
    for (final c in [
      _context,
      _youtube,
      _topic,
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

  Future<void> _resolveSelection() async {
    setState(() {
      _selectionLoading = true;
      _selectionError = null;
    });
    try {
      final sel = await ref.read(aiServiceProvider).resolveSelection();
      if (!mounted) return;
      setState(() {
        _selection = sel;
        _selectionLoading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _selection = null;
        _selectionError = e;
        _selectionLoading = false;
      });
    }
  }

  Future<void> _openSettings() async {
    await context.push(AppRoutes.settings);
    if (mounted) await _resolveSelection();
  }

  String? get _subjectId =>
      _note?.subjectId ?? widget.subjectId ?? _pickedSubjectId;

  // ---------------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------------

  String? get _youtubeError {
    final text = _youtube.text.trim();
    if (text.isEmpty) return null;
    return YoutubeUrl.parseVideoId(text) == null
        ? "That doesn't look like a YouTube video link."
        : null;
  }

  String? get _sourceError =>
      _context.text.trim().isEmpty && _youtube.text.trim().isEmpty
      ? 'Paste some text or add a YouTube link to generate from.'
      : null;

  String? get _subjectError =>
      _subjectId == null ? 'Choose where to save the result.' : null;

  String? get _typesError =>
      _isQuiz && _types.isEmpty ? 'Pick at least one question type.' : null;

  bool get _inputValid =>
      _youtubeError == null &&
      _sourceError == null &&
      _subjectError == null &&
      _typesError == null;

  // ---------------------------------------------------------------------------
  // Generation
  // ---------------------------------------------------------------------------

  String? _blankToNull(String s) => s.trim().isEmpty ? null : s.trim();

  String? get _topicValue {
    final typed = _blankToNull(_topic.text);
    if (typed != null) return typed;
    if (_note != null) return _note!.title;
    final id = _subjectId;
    return id == null ? null : ref.read(subjectProvider(id)).value?.title;
  }

  Future<void> _generate() async {
    setState(() => _validated = true);
    if (!_inputValid) return;
    FocusScope.of(context).unfocus();
    final gen = ++_generation;
    setState(() {
      _stage = _Stage.generating;
      _error = null;
    });
    final ai = ref.read(aiServiceProvider);
    final contextText = _blankToNull(_context.text);
    final youtube = _youtube.text.trim().isEmpty
        ? null
        : YoutubeUrl.normalize(_youtube.text);
    try {
      final sel = _selection ?? await ai.resolveSelection();
      if (_isQuiz) {
        final request = QuizGenerationRequest(
          contextText: contextText,
          youtubeUrl: youtube,
          questionCount: _count,
          questionTypes: {..._types},
          difficulty: _difficulty,
          language: _blankToNull(_language.text),
          extraInstructions: _blankToNull(_instructions.text),
          topic: _topicValue,
          providerId: sel.providerId,
          model: sel.model,
        );
        final draft = await ai.generateQuiz(request);
        if (gen != _generation || !mounted) return;
        final newId = ref.read(idGeneratorProvider);
        setState(() {
          _used = sel;
          _quizRequest = request;
          _usedContext = contextText;
          _usedYoutube = youtube;
          _draftTitle.text = draft.title;
          _draftDescription.text = draft.description ?? '';
          _questions = draft.toQuestions(newId);
          _resetPreviewState();
        });
      } else {
        final request = NoteGenerationRequest(
          contextText: contextText,
          youtubeUrl: youtube,
          language: _blankToNull(_language.text),
          extraInstructions: _blankToNull(_instructions.text),
          topic: _topicValue,
          providerId: sel.providerId,
          model: sel.model,
        );
        final draft = await ai.generateNote(request);
        if (gen != _generation || !mounted) return;
        setState(() {
          _used = sel;
          _usedContext = contextText;
          _usedYoutube = youtube;
          _draftTitle.text = draft.title;
          _noteBody.text = draft.contentMarkdown;
          _resetPreviewState();
        });
      }
    } on Object catch (e) {
      if (gen != _generation || !mounted) return;
      setState(() {
        _error = e;
        _stage = _Stage.form;
      });
      if (e is AiException && e.kind == AiErrorKind.missingApiKey) {
        await _resolveSelection();
      }
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
        final ctx = _usedContext;
        final quiz = await ref
            .read(quizRepositoryProvider)
            .create(
              subjectId: subjectId,
              noteId: widget.noteId,
              title: title,
              description: _blankToNull(_draftDescription.text),
              questions: [for (final q in _questions) normalizeQuestion(q)],
              source: QuizSource(
                contextText: ctx == null || ctx.length <= _maxStoredContext
                    ? ctx
                    : ctx.substring(0, _maxStoredContext),
                youtubeUrl: _usedYoutube,
                provider: _used?.providerId.wireName,
                model: _used?.model,
              ),
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
    final title = switch ((_isQuiz, _stage)) {
      (true, _Stage.preview) => 'Review quiz',
      (false, _Stage.preview) => 'Review note',
      (true, _) => 'Generate quiz with AI',
      (false, _) => 'Generate note with AI',
    };
    return PopScope(
      canPop: _stage == _Stage.form,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onPopBlocked();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: switch (_stage) {
          _Stage.form => _form(context),
          _Stage.generating => _progress(context),
          _Stage.preview => _isQuiz ? _quizPreview(context) : _notePreview(),
        },
        bottomNavigationBar: _stage == _Stage.preview
            ? _previewActions(context)
            : null,
      ),
    );
  }

  // --- Form -------------------------------------------------------------------

  Widget _form(BuildContext context) {
    final theme = Theme.of(context);
    final v = _validated;

    final source = _Section(
      title: 'Source material',
      icon: Icons.article_outlined,
      children: [
        TextField(
          key: const Key('ai-context'),
          controller: _context,
          minLines: 6,
          maxLines: 16,
          decoration: InputDecoration(
            labelText: 'Text to learn from',
            hintText: 'Paste notes, an article, a transcript…',
            alignLabelWithHint: true,
            errorText: v ? _sourceError : null,
            helperText: widget.noteId != null && _note != null
                ? 'Prefilled with the note "${_note!.title}".'
                : null,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('ai-youtube'),
          controller: _youtube,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: 'YouTube video (optional)',
            hintText: 'https://www.youtube.com/watch?v=…',
            prefixIcon: const Icon(Icons.smart_display_outlined),
            errorText: _youtubeError,
            helperText:
                'Gemini watches the video directly; other providers use the '
                "video's captions.",
            helperMaxLines: 2,
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (kIsWeb &&
            _youtube.text.trim().isNotEmpty &&
            _selection != null &&
            !_selection!.providerId.supportsYoutubeUrl) ...[
          const SizedBox(height: 12),
          _Notice(
            icon: Icons.warning_amber_rounded,
            text:
                'In the browser, YouTube usually blocks caption downloads '
                '(CORS), so ${_selection!.providerId.displayName} may not be '
                'able to use this video. Switch to Gemini in Settings, or '
                'paste the transcript above.',
          ),
        ],
        const SizedBox(height: 16),
        TextField(
          key: const Key('ai-topic'),
          controller: _topic,
          decoration: InputDecoration(
            labelText: 'Topic or focus (optional)',
            hintText: _topicHint(),
          ),
        ),
      ],
    );

    final options = _Section(
      title: _isQuiz ? 'Quiz options' : 'Note options',
      icon: Icons.tune,
      children: [
        if (_isQuiz) ...[
          Row(
            children: [
              Text('Questions', style: theme.textTheme.labelLarge),
              const Spacer(),
              Text('$_count', style: theme.textTheme.titleMedium),
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
          const SizedBox(height: 8),
          Text('Question types', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in QuestionType.values)
                FilterChip(
                  avatar: Icon(questionTypeIcon(t), size: 18),
                  label: Text(questionTypeLabel(t)),
                  selected: _types.contains(t),
                  showCheckmark: false,
                  onSelected: (on) => setState(() {
                    _types = on ? ({..._types, t}) : ({..._types}..remove(t));
                  }),
                ),
            ],
          ),
          if (v && _typesError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _typesError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text('Difficulty', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<Difficulty>(
            segments: const [
              ButtonSegment(value: Difficulty.easy, label: Text('Easy')),
              ButtonSegment(value: Difficulty.medium, label: Text('Medium')),
              ButtonSegment(value: Difficulty.hard, label: Text('Hard')),
            ],
            selected: {_difficulty},
            onSelectionChanged: (s) => setState(() => _difficulty = s.first),
          ),
          const SizedBox(height: 16),
        ],
        TextField(
          controller: _language,
          decoration: const InputDecoration(
            labelText: 'Language (optional)',
            hintText: 'Same as the source, e.g. English, Deutsch',
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _instructions,
          minLines: 1,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: 'Extra instructions (optional)',
            hintText: _isQuiz
                ? 'e.g. Focus on dates and definitions'
                : 'e.g. Concise summary with headings and key terms',
          ),
        ),
      ],
    );

    final target = _targetSection(context);
    final generate = FilledButton.icon(
      key: const Key('ai-generate'),
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      onPressed: _selection == null && !_selectionLoading ? null : _generate,
      icon: const Icon(Icons.auto_awesome),
      label: Text(_isQuiz ? 'Generate quiz' : 'Generate note'),
    );
    final providerCard = _providerCard(context);
    final error = _error == null
        ? null
        : AiErrorCard(
            error: _error!,
            onOpenSettings: _openSettings,
            onRetry: _generate,
            onDismiss: () => setState(() => _error = null),
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 1000) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: MaxWidth(
              maxWidth: 1200,
              child: Column(
                children: [
                  if (error != null) ...[error, const SizedBox(height: 16)],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: source),
                      const SizedBox(width: 24),
                      SizedBox(
                        width: 400,
                        child: Column(
                          children: [
                            providerCard,
                            const SizedBox(height: 16),
                            ?target,
                            if (target != null) const SizedBox(height: 16),
                            options,
                            const SizedBox(height: 16),
                            generate,
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            MaxWidth(
              maxWidth: 760,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (error != null) ...[error, const SizedBox(height: 16)],
                  providerCard,
                  const SizedBox(height: 16),
                  ?target,
                  if (target != null) const SizedBox(height: 16),
                  source,
                  const SizedBox(height: 16),
                  options,
                  const SizedBox(height: 24),
                  generate,
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  String? _topicHint() {
    if (_note != null) return _note!.title;
    final id = _subjectId;
    return id == null ? null : ref.watch(subjectProvider(id)).value?.title;
  }

  Widget _providerCard(BuildContext context) {
    final theme = Theme.of(context);
    if (_selectionLoading) {
      return const Card(
        child: ListTile(
          leading: SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          title: Text('Checking AI settings…'),
        ),
      );
    }
    final sel = _selection;
    if (sel != null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.auto_awesome),
          title: Text('Using ${sel.providerId.displayName}'),
          subtitle: Text(sel.model),
          trailing: TextButton(
            onPressed: _openSettings,
            child: const Text('Change'),
          ),
        ),
      );
    }
    final info = describeAiError(_selectionError ?? Object());
    return Card(
      key: const Key('ai-no-provider'),
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.key_off_outlined,
                  color: theme.colorScheme.onTertiaryContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(info.title, style: theme.textTheme.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(info.hint ?? info.message),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: _openSettings,
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Open settings'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget? _targetSection(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.noteId != null) {
      final note = _note;
      return _Section(
        title: 'Save to',
        icon: Icons.description_outlined,
        children: [
          Text(
            note == null
                ? 'Loading note…'
                : _isQuiz
                ? 'Quiz for the note "${note.title}"'
                : 'New note in the same subject as "${note.title}"',
            style: theme.textTheme.bodyLarge,
          ),
        ],
      );
    }
    if (widget.subjectId != null) {
      final subject = ref.watch(subjectProvider(widget.subjectId!)).value;
      return _Section(
        title: 'Save to',
        icon: Icons.folder_outlined,
        children: [
          Text(
            subject == null ? 'Loading subject…' : subject.title,
            style: theme.textTheme.bodyLarge,
          ),
        ],
      );
    }
    final subjects = ref.watch(subjectsProvider);
    return _Section(
      title: 'Save to',
      icon: Icons.folder_outlined,
      children: [
        switch (subjects) {
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
              errorText: _validated ? _subjectError : null,
            ),
            items: [
              for (final s in value)
                DropdownMenuItem(
                  value: s.id,
                  child: Text(s.title, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (id) => setState(() => _pickedSubjectId = id),
          ),
          AsyncValue(:final error?) => Text(errorText(error)),
          _ => const LinearProgressIndicator(),
        },
      ],
    );
  }

  // --- Progress ----------------------------------------------------------------

  Widget _progress(BuildContext context) {
    final theme = Theme.of(context);
    final sel = _selection;
    final usesCaptions =
        _youtube.text.trim().isNotEmpty &&
        sel != null &&
        !sel.providerId.supportsYoutubeUrl;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox.square(
                dimension: 56,
                child: CircularProgressIndicator(strokeWidth: 5),
              ),
              const SizedBox(height: 24),
              Text(
                _isQuiz ? 'Generating your quiz…' : 'Writing your note…',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                [
                  if (sel != null)
                    'Using ${sel.providerId.displayName} · ${sel.model}.',
                  if (usesCaptions) "Fetching the video's captions first.",
                  'This can take up to a couple of minutes.',
                ].join(' '),
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                key: const Key('ai-cancel'),
                onPressed: _cancel,
                icon: const Icon(Icons.close),
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
    final theme = Theme.of(context);
    final used = _used;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: _Notice(
        icon: Icons.auto_awesome,
        text:
            'Review and edit the draft before saving. AI can make mistakes.'
            '${used == null ? '' : ' Generated by ${used.providerId.displayName} · ${used.model}.'}',
        color: theme.colorScheme.secondaryContainer,
      ),
    );
  }

  Widget _quizPreview(BuildContext context) {
    final theme = Theme.of(context);
    final header = Padding(
      padding: const EdgeInsets.only(bottom: 16),
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
          const SizedBox(height: 12),
          TextField(
            controller: _draftDescription,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
            ),
            onChanged: (_) => _draftDirty = true,
          ),
          const SizedBox(height: 20),
          Text(
            'Questions (${_questions.length})',
            style: theme.textTheme.titleMedium,
          ),
        ],
      ),
    );
    return MaxWidth(
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
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
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
    return Material(
      elevation: 3,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: busy ? null : _backToOptions,
                icon: const Icon(Icons.arrow_back),
                label: const Text('Options'),
              ),
              const Spacer(),
              Flexible(
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      key: const Key('ai-regenerate'),
                      onPressed: busy ? null : _regenerateAll,
                      icon: const Icon(Icons.autorenew),
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
                          : const Icon(Icons.check),
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

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(title, style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color ?? theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
