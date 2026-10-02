import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ai/ai_capabilities.dart';
import '../../../ai/ai_chat_service.dart' as ai;
import '../../../ai/chat_context.dart' show ChatBudget;
import '../../../data/data_providers.dart';
import '../../../data/models/models.dart';
import '../../ai_generate/domain/generation_sources.dart'
    show fileKindProblem, isTextAttachment;
import 'chat_format.dart';

typedef ChatScopeKey = ({ChatScopeType type, String? id});

/// What a chat is about, resolved from the local cache.
@immutable
class ChatScopeData {
  const ChatScopeData({
    required this.type,
    this.id,
    this.title,
    this.subject,
    this.notes = const [],
    this.files = const [],
  });

  final ChatScopeType type;
  final String? id;

  /// Subject / note / file name; null when the scope is gone (deleted,
  /// share revoked) or general.
  final String? title;
  final Subject? subject;

  /// Candidate notes / files, in a stable order (oldest first) so source
  /// numbering stays the same between messages.
  final List<Note> notes;
  final List<Attachment> files;

  /// False when the scope no longer exists locally ("source unavailable").
  bool get available => type == ChatScopeType.general || title != null;

  /// Subject description, offered as a small "overview" source.
  String? get overview {
    final d = subject?.description?.trim() ?? '';
    return d.isEmpty ? null : d;
  }
}

int _byCreated(DateTime a, String aId, DateTime b, String bId) {
  final c = a.compareTo(b);
  return c != 0 ? c : aId.compareTo(bId);
}

/// Scope data of a chat, combined from the subject / note / attachment
/// providers.
final chatScopeDataProvider = Provider.autoDispose
    .family<AsyncValue<ChatScopeData>, ChatScopeKey>((ref, scope) {
      final id = scope.id;
      if (scope.type == ChatScopeType.general || id == null) {
        return const AsyncData(ChatScopeData(type: ChatScopeType.general));
      }
      switch (scope.type) {
        case ChatScopeType.subject:
          final subject = ref.watch(subjectProvider(id));
          final notes = ref.watch(notesBySubjectProvider(id));
          final files = ref.watch(attachmentsForSubjectProvider(id));
          if (subject case AsyncError(:final error, :final stackTrace)) {
            return AsyncError(error, stackTrace);
          }
          bool pending(AsyncValue<Object?> v) => !v.hasValue && !v.hasError;
          if (subject.hasValue && subject.value == null) {
            return AsyncData(ChatScopeData(type: scope.type, id: id));
          }
          if (pending(subject) || pending(notes) || pending(files)) {
            return const AsyncLoading();
          }
          final s = subject.value;
          return AsyncData(
            ChatScopeData(
              type: scope.type,
              id: id,
              title: s?.title,
              subject: s,
              notes: [...?notes.value]
                ..sort(
                  (a, b) => _byCreated(a.createdAt, a.id, b.createdAt, b.id),
                ),
              files: [...?files.value]
                ..sort(
                  (a, b) => _byCreated(a.createdAt, a.id, b.createdAt, b.id),
                ),
            ),
          );
        case ChatScopeType.note:
          return ref
              .watch(noteProvider(id))
              .whenData(
                (n) => ChatScopeData(
                  type: scope.type,
                  id: id,
                  title: n?.title,
                  notes: [?n],
                ),
              );
        case ChatScopeType.attachment:
          return ref
              .watch(attachmentProvider(id))
              .whenData(
                (a) => ChatScopeData(
                  type: scope.type,
                  id: id,
                  title: a?.name,
                  files: [?a],
                ),
              );
        case ChatScopeType.general:
          return const AsyncData(ChatScopeData(type: ChatScopeType.general));
      }
    });

/// Id used for the subject overview source in a [ChatSourceSelection].
String overviewKey(String subjectId) => 'overview:$subjectId';

/// Which candidate sources are included. `null` ids = the default.
@immutable
class ChatSourceSelection {
  const ChatSourceSelection(this.ids);

  final Set<String> ids;

  bool contains(String id) => ids.contains(id);

  ChatSourceSelection toggle(String id) => ChatSourceSelection(
    ids.contains(id) ? ({...ids}..remove(id)) : {...ids, id},
  );

  /// Default: subject → its overview and all notes that fit the context
  /// budget (oldest first, at least one), no files; note / file → that
  /// item (files only when the model can read them).
  factory ChatSourceSelection.defaults(
    ChatScopeData scope,
    AiCapabilities caps, {
    int? budget,
  }) {
    switch (scope.type) {
      case ChatScopeType.subject:
        final maxChars = budget ?? const ChatBudget().maxContextChars;
        final ids = <String>{};
        var used = 0;
        if (scope.overview case final o?) {
          ids.add(overviewKey(scope.id!));
          used += o.length;
        }
        var first = true;
        for (final n in scope.notes) {
          final len = n.contentMd.length + n.title.length;
          if (!first && used + len > maxChars) break;
          ids.add(n.id);
          used += len;
          first = false;
        }
        return ChatSourceSelection(ids);
      case ChatScopeType.note:
        return ChatSourceSelection({for (final n in scope.notes) n.id});
      case ChatScopeType.attachment:
        return ChatSourceSelection({
          for (final a in scope.files)
            if (fileKindProblem(a.kind, caps) == null) a.id,
        });
      case ChatScopeType.general:
        return const ChatSourceSelection({});
    }
  }
}

/// The AI context for one request and the stored citation type of every
/// source id.
typedef ChatContextSources = ({
  List<ai.AiSource> sources,
  Map<String, String> typeById,
});

/// Builds the request context from the selected candidates, in a stable
/// order: notes, files, subject overview. Files the model can't read are
/// skipped; text files use their extracted text. [loadBytes] fetches the
/// other files (may throw, e.g. offline and not cached).
Future<ChatContextSources> buildChatContext(
  ChatScopeData scope,
  ChatSourceSelection selection,
  AiCapabilities caps,
  Future<Uint8List> Function(Attachment a) loadBytes,
) async {
  final sources = <ai.AiSource>[];
  final types = <String, String>{};
  for (final n in scope.notes) {
    if (!selection.contains(n.id)) continue;
    sources.add(ai.NoteSource(id: n.id, title: n.title, markdown: n.contentMd));
    types[n.id] = CitationTypes.note;
  }
  for (final a in scope.files) {
    if (!selection.contains(a.id)) continue;
    final text = a.extractedText ?? '';
    if (isTextAttachment(a) && text.trim().isNotEmpty) {
      sources.add(
        ai.TextSource(
          id: a.id,
          label: a.name,
          text: text,
          type: ai.AiSourceType.file,
        ),
      );
    } else if (fileKindProblem(a.kind, caps) == null) {
      sources.add(
        ai.FileSource(
          id: a.id,
          name: a.name,
          mimeType: a.mimeType,
          bytes: await loadBytes(a),
        ),
      );
    } else {
      continue;
    }
    types[a.id] = CitationTypes.attachment;
  }
  final subject = scope.subject;
  if (subject != null &&
      scope.overview != null &&
      selection.contains(overviewKey(subject.id))) {
    sources.add(
      ai.TextSource(
        id: subject.id,
        label: subject.title,
        text: '# ${subject.title}\n\n${scope.overview}',
      ),
    );
    types[subject.id] = CitationTypes.subject;
  }
  return (sources: sources, typeById: types);
}
