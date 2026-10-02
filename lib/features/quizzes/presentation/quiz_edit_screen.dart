import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/question.dart';
import '../../../data/models/quiz.dart';
import '../../../data/models/syncable.dart';
import '../domain/question_rules.dart';
import '../widgets/question_list_editor.dart';
import '../widgets/quiz_format.dart';

/// Result of the "unsaved changes" prompt.
enum _LeaveChoice { save, discard }

/// Owner-only editor: title, description and the question list.
class QuizEditScreen extends ConsumerStatefulWidget {
  const QuizEditScreen({super.key, required this.quizId});

  final String quizId;

  @override
  ConsumerState<QuizEditScreen> createState() => _QuizEditScreenState();
}

class _QuizEditScreenState extends ConsumerState<QuizEditScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  Quiz? _original;
  List<Question> _questions = [];
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

  void _init(Quiz quiz) {
    _original = quiz;
    _title.text = quiz.title;
    _description.text = quiz.description ?? '';
    _questions = [...quiz.questions];
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  /// Saves; returns true on success.
  Future<bool> _save() async {
    final original = _original;
    if (original == null || _saving) return false;
    final title = _title.text.trim();
    final invalid = _questions.where((q) => validateQuestion(q).isNotEmpty);
    setState(() {
      _titleError = title.isEmpty ? 'Give the quiz a title.' : null;
      _showIssues = true;
    });
    if (title.isEmpty || invalid.isNotEmpty) {
      showSnack(
        context,
        invalid.isNotEmpty
            ? 'Fix ${plural(invalid.length, 'question')} marked in red '
                  'before saving.'
            : 'Give the quiz a title.',
      );
      return false;
    }
    setState(() => _saving = true);
    try {
      final description = _description.text.trim();
      final saved = await ref
          .read(quizRepositoryProvider)
          .update(
            original.copyWith(
              title: title,
              description: description.isEmpty ? null : description,
              questions: [for (final q in _questions) normalizeQuestion(q)],
            ),
          );
      if (!mounted) return true;
      setState(() {
        _original = saved;
        _questions = [...saved.questions];
        _dirty = false;
        _showIssues = false;
      });
      showSnack(context, 'Quiz saved');
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
    _leave();
  }

  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.quiz(widget.quizId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final quizAsync = ref.watch(quizProvider(widget.quizId));
    final userId = ref.watch(currentUserIdProvider);
    final loaded = quizAsync.value;
    if (_original == null && loaded != null) _init(loaded);

    final Widget body;
    if (_original != null) {
      body = _original!.isOwnedBy(userId)
          ? _editor(context)
          : const MessageView(
              icon: Icons.lock_outline,
              title: 'Read-only quiz',
              message:
                  'This quiz is shared with you. Copy it to your account to '
                  'edit it.',
            );
    } else if (quizAsync.hasValue) {
      body = const MessageView(icon: Icons.search_off, title: 'Quiz not found');
    } else if (quizAsync.hasError) {
      body = MessageView(
        icon: Icons.error_outline,
        title: 'Could not load the quiz',
        message: errorText(quizAsync.error!),
      );
    } else {
      body = const Center(child: CircularProgressIndicator());
    }

    final canEdit = _original?.isOwnedBy(userId) ?? false;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Edit quiz'),
          actions: [
            if (canEdit)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: FilledButton.icon(
                  key: const Key('save-quiz'),
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
    );
  }

  Widget _editor(BuildContext context) {
    final theme = Theme.of(context);
    final header = Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('quiz-title'),
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
          const SizedBox(height: 12),
          TextField(
            key: const Key('quiz-description'),
            controller: _description,
            minLines: 1,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
            ),
            onChanged: (_) => _markDirty(),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Text(
                'Questions (${_questions.length})',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(width: 12),
              if (_questions.length > 1)
                Expanded(
                  child: Text(
                    'Drag to reorder',
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
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
        onChanged: (list) {
          setState(() {
            _questions = list;
            _dirty = true;
          });
        },
      ),
    );
  }
}
