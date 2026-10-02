import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../ai/ai_tools_service.dart';
import '../../../core/router/routes.dart';
import '../../../core/widgets/design_system.dart' hide MaxWidth;
import '../../../core/widgets/note_markdown.dart';
import '../../../data/models/question.dart';
import '../../../data/models/quiz.dart';
import '../../../data/models/quiz_attempt.dart';
import '../application/answer_explainer.dart';
import 'quiz_format.dart';

/// "Explain" action for one question (AI-gated): opens [showExplainSheet].
/// While AI is not set up it shows a lock and opens the setup sheet.
class ExplainButton extends StatelessWidget {
  const ExplainButton({
    super.key,
    required this.question,
    this.answer,
    this.quiz,
    this.compact = false,
  });

  final Question question;

  /// The user's answer (null = unknown; explains the correct answer only).
  final QuestionAnswer? answer;

  /// The quiz, whose notes are used as context.
  final Quiz? quiz;

  /// Icon-only (for list rows).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    void open() => showExplainSheet(
      context,
      ExplainTarget(question: question, answer: answer, quiz: quiz),
    );
    return AiGate(
      onReady: open,
      child: compact
          ? IconButton(
              key: Key('explain-${question.id}'),
              tooltip: 'Explain with AI',
              icon: const Icon(Icons.auto_awesome_outlined, size: 18),
              onPressed: open,
            )
          : TextButton.icon(
              key: Key('explain-${question.id}'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: Insets.sm),
              ),
              onPressed: open,
              icon: const Icon(Icons.auto_awesome_outlined, size: 16),
              label: const Text('Explain'),
            ),
    );
  }
}

/// The AI explanation of [target] (loading, error with retry, Markdown and
/// source chips that open the cited notes) in an adaptive panel: a
/// content-height bottom sheet on phones, a dialog up to 640 wide and 80%
/// of the screen height elsewhere. Long explanations scroll inside.
Future<void> showExplainSheet(BuildContext context, ExplainTarget target) {
  final router = GoRouter.of(context);
  return showAdaptivePanel<void>(
    context,
    maxWidth: 640,
    builder: (panelContext) => ExplainPanel(
      target: target,
      onOpenNote: (id) {
        Navigator.of(panelContext).pop();
        router.push(AppRoutes.note(id));
      },
    ),
  );
}

/// Contents of the explanation sheet.
class ExplainPanel extends ConsumerStatefulWidget {
  const ExplainPanel({
    super.key,
    required this.target,
    required this.onOpenNote,
    this.scrollController,
  });

  final ExplainTarget target;
  final ValueChanged<String> onOpenNote;
  final ScrollController? scrollController;

  @override
  ConsumerState<ExplainPanel> createState() => _ExplainPanelState();
}

class _ExplainPanelState extends ConsumerState<ExplainPanel> {
  late Future<AiExplanation> _future;

  @override
  void initState() {
    super.initState();
    _future = explainAnswer(ref, widget.target);
  }

  void _retry() {
    final next = explainAnswer(ref, widget.target);
    setState(() {
      _future = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final q = widget.target.question;
    return FutureBuilder<AiExplanation>(
      future: _future,
      builder: (context, snap) {
        final children = <Widget>[
          Row(
            children: [
              Icon(
                Icons.auto_awesome_outlined,
                size: 18,
                color: colors.mutedText,
              ),
              Gaps.w8,
              Text('Explanation', style: theme.textTheme.titleMedium),
            ],
          ),
          Gaps.h8,
          Text(
            q.prompt,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.mutedText,
            ),
          ),
          Gaps.h16,
        ];
        if (snap.hasError) {
          children.add(
            InfoBanner(
              key: const Key('explain-error'),
              kind: InfoBannerKind.error,
              message: 'Could not explain this: ${errorText(snap.error!)}',
              action: TextButton(
                key: const Key('explain-retry'),
                onPressed: _retry,
                child: const Text('Try again'),
              ),
            ),
          );
        } else if (!snap.hasData) {
          children.add(
            Row(
              key: const Key('explain-loading'),
              children: [
                const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                Gaps.w12,
                Expanded(
                  child: Text(
                    'Writing an explanation…',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.mutedText,
                    ),
                  ),
                ),
              ],
            ),
          );
        } else {
          final e = snap.data!;
          children.add(
            NoteMarkdown(key: const Key('explain-markdown'), data: e.markdown),
          );
          final notes = [
            for (final c in e.citations)
              if (c.id != null) c,
          ];
          if (notes.isNotEmpty) {
            children.addAll([
              Gaps.h16,
              Text(
                'Sources',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.mutedText,
                ),
              ),
              Gaps.h8,
              Wrap(
                spacing: Insets.sm,
                runSpacing: Insets.sm,
                children: [
                  for (final c in notes)
                    ActionChip(
                      key: Key('explain-citation-${c.number}'),
                      avatar: Icon(
                        c.type == AiSourceType.note
                            ? Icons.description_outlined
                            : Icons.attach_file,
                        size: 16,
                      ),
                      label: Text('${c.marker} · ${c.title}'),
                      tooltip: c.type == AiSourceType.note ? 'Open note' : null,
                      onPressed: c.type == AiSourceType.note
                          ? () => widget.onOpenNote(c.id!)
                          : null,
                    ),
                ],
              ),
            ]);
          }
          children.addAll([
            Gaps.h16,
            Text(
              'AI · ${e.selection.providerId.displayName} · '
              '${e.selection.model}. Check important facts.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.faintText,
              ),
            ),
          ]);
        }
        return ListView(
          key: const Key('explain-panel'),
          controller: widget.scrollController,
          shrinkWrap: widget.scrollController == null,
          padding: EdgeInsets.fromLTRB(
            Insets.xl,
            Breakpoints.isMedium(context) ? Insets.xl : 0,
            Insets.xl,
            Insets.xl,
          ),
          children: children,
        );
      },
    );
  }
}
