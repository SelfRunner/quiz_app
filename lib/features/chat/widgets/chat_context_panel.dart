import 'package:flutter/material.dart';

import '../../../ai/ai_capabilities.dart';
import '../../../ai/ai_chat_service.dart' as ai;
import '../../../core/widgets/design_system.dart';
import '../../../data/models/models.dart';
import '../../ai_generate/domain/generation_sources.dart'
    show attachmentKindIcon, fileKindProblem, formatFileSize, isTextAttachment;
import '../application/chat_format.dart';
import '../application/chat_sources.dart';

/// What the chat is about and which sources the next answer may use.
/// Subjects offer a checklist of notes and files (files the model can't
/// read are disabled with the reason); a note / file chat shows that item.
class ChatContextPanel extends StatelessWidget {
  const ChatContextPanel({
    super.key,
    required this.scope,
    required this.selection,
    required this.capabilities,
    required this.onToggle,
    this.lastSources = const [],
  });

  final ChatScopeData scope;
  final ChatSourceSelection selection;
  final AiCapabilities capabilities;
  final ValueChanged<String> onToggle;

  /// How the last request used the sources (omitted / unreadable notes).
  final List<ai.ChatSourceRef> lastSources;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final notices = [
      for (final s in lastSources)
        if (s.status != ai.ChatSourceStatus.full && s.note != null)
          '${s.title}: ${s.note}',
    ];
    final selectedCount = _selectedCount();
    return ListView(
      key: const Key('chat-context-panel'),
      padding: const EdgeInsets.all(Insets.lg),
      children: [
        Text(
          scopeKindLabel(scope.type).toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: colors.faintText,
            letterSpacing: 0.6,
          ),
        ),
        Gaps.h4,
        Row(
          children: [
            Icon(scopeIcon(scope.type), size: 18, color: colors.mutedText),
            Gaps.w8,
            Expanded(
              child: Text(
                scope.type == ChatScopeType.general
                    ? 'General chat'
                    : scope.title ?? 'Source unavailable',
                style: theme.textTheme.titleSmall,
              ),
            ),
          ],
        ),
        Gaps.h12,
        if (!scope.available)
          const InfoBanner(
            key: Key('chat-scope-unavailable'),
            kind: InfoBannerKind.warning,
            message:
                'This item was deleted or is no longer shared with you. You '
                'can still read this chat; new answers can’t use it.',
          )
        else if (scope.type == ChatScopeType.general)
          Text(
            'No sources: answers use the model’s general knowledge.',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.mutedText),
          )
        else ...[
          Text(
            selectedCount == 0
                ? 'No sources included'
                : '$selectedCount source${selectedCount == 1 ? '' : 's'} '
                      'included',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.mutedText),
          ),
          Gaps.h8,
          if (scope.overview != null && scope.subject != null)
            _SourceTile(
              id: overviewKey(scope.subject!.id),
              icon: Icons.folder_outlined,
              title: 'Subject overview',
              subtitle: 'Description of ${scope.subject!.title}',
              selected: selection.contains(overviewKey(scope.subject!.id)),
              onToggle: onToggle,
            ),
          if (scope.type == ChatScopeType.subject) ...[
            _GroupLabel('Notes', count: scope.notes.length),
            if (scope.notes.isEmpty) const _Empty('No notes in this subject'),
          ],
          for (final n in scope.notes)
            _SourceTile(
              id: n.id,
              icon: Icons.description_outlined,
              title: n.title.isEmpty ? 'Untitled note' : n.title,
              subtitle: '${_words(n.contentMd)} words',
              selected: selection.contains(n.id),
              onToggle: scope.type == ChatScopeType.subject ? onToggle : null,
            ),
          if (scope.type == ChatScopeType.subject) ...[
            _GroupLabel('Files', count: scope.files.length),
            if (scope.files.isEmpty) const _Empty('No files in this subject'),
          ],
          for (final a in scope.files) _fileTile(a),
        ],
        if (notices.isNotEmpty) ...[
          Gaps.h12,
          InfoBanner(
            key: const Key('chat-source-notices'),
            kind: InfoBannerKind.info,
            title: 'Not fully used in the last answer',
            message: notices.join('\n'),
          ),
        ],
      ],
    );
  }

  int _selectedCount() {
    var n = 0;
    if (scope.subject != null &&
        scope.overview != null &&
        selection.contains(overviewKey(scope.subject!.id))) {
      n++;
    }
    n += scope.notes.where((x) => selection.contains(x.id)).length;
    n += scope.files
        .where(
          (a) =>
              selection.contains(a.id) &&
              fileKindProblem(a.kind, capabilities) == null,
        )
        .length;
    return n;
  }

  Widget _fileTile(Attachment a) {
    final problem = isTextAttachment(a)
        ? null
        : fileKindProblem(a.kind, capabilities);
    final selectable = problem == null;
    return _SourceTile(
      id: a.id,
      icon: attachmentKindIcon(a.kind),
      title: a.name,
      subtitle: problem ?? formatFileSize(a.sizeBytes),
      warning: problem != null,
      selected: selectable && selection.contains(a.id),
      onToggle: selectable && scope.type == ChatScopeType.subject
          ? onToggle
          : null,
      lockedOff: !selectable,
    );
  }

  static int _words(String text) => RegExp(r'\S+').allMatches(text).length;
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label, {required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Insets.md, bottom: Insets.xs),
      child: Text(
        '$label · $count',
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: colors.mutedText),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Insets.xs),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: AppColors.of(context).faintText),
    ),
  );
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.id,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    this.onToggle,
    this.warning = false,
    this.lockedOff = false,
  });

  final String id;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;

  /// Null = fixed (note / file chats) or disabled.
  final ValueChanged<String>? onToggle;
  final bool warning;
  final bool lockedOff;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final toggle = onToggle;
    return InkWell(
      key: Key('chat-source-$id'),
      borderRadius: Radii.mdAll,
      onTap: toggle == null ? null : () => toggle(id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Insets.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: lockedOff
                  ? Icon(Icons.block, size: 16, color: colors.faintText)
                  : Checkbox(
                      key: Key('chat-source-check-$id'),
                      value: selected,
                      visualDensity: VisualDensity.compact,
                      onChanged: toggle == null ? null : (_) => toggle(id),
                    ),
            ),
            Gaps.w4,
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Icon(icon, size: 16, color: colors.mutedText),
            ),
            Gaps.w8,
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: lockedOff ? colors.mutedText : null,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: warning ? colors.warning : colors.faintText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
