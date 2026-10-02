import '../core/errors/app_exception.dart';
import 'ai_capabilities.dart';
import 'ai_chat_service.dart';
import 'chat_context.dart';
import 'llm_provider.dart';
import 'llm_resolver.dart';
import 'providers/attachment_support.dart';
import 'text_extractor.dart';
import 'transcript_service.dart';
import 'youtube_url.dart';

/// Turns `AiSource`s into numbered, budgeted prompt material (`[S1]`,
/// `[S2]`, ...) for chat and the source-grounded quiz helpers.
class SourceContextBuilder {
  SourceContextBuilder({
    required this.resolver,
    required this.transcripts,
    this.maxContextChars = 60000,
    this.minExcerptChars = 2000,
  });

  final LlmResolver resolver;
  final TranscriptService transcripts;

  /// See [ChatBudget.maxContextChars].
  final int maxContextChars;

  /// See [ChatBudget.minExcerptChars].
  final int minExcerptChars;

  /// Numbers [context] (`S1`, `S2`, ... in list order), turns each source
  /// into prompt text or an attachment the resolved model can read (others
  /// become [ChatSourceStatus.unreadable] with a reason instead of failing
  /// the request) and fits the texts into [budget] (see
  /// [allocateTextBudget] / [excerptText]).
  Future<PreparedSources> build(
    List<AiSource> context,
    ResolvedLlm resolved,
  ) async {
    final selection = resolved.selection;
    final id = selection.providerId;
    final needsCaps = context.any(
      (s) =>
          s is YoutubeSource || (s is FileSource && s.kind != AiInputKind.text),
    );
    final caps = needsCaps
        ? await resolver.capabilitiesFor(selection, resolved.baseUrl)
        : AiCapabilities.textOnly;
    final limits = ProviderLimits.forProvider(id);
    final who = '${selection.model} (${id.displayName})';

    final refs = <ChatSourceRef>[];
    final texts = <int, String>{};
    final attachments = <LlmAttachment>[];
    final attached = <int>{};
    var attachedBytes = 0;

    ChatSourceRef ref(
      int n,
      AiSource s,
      String title, [
      ChatSourceStatus status = ChatSourceStatus.full,
      String? note,
    ]) => ChatSourceRef(
      number: n,
      type: s.type,
      id: s.id,
      title: title,
      status: status,
      note: note,
    );

    for (var i = 0; i < context.length; i++) {
      final s = context[i];
      final n = i + 1;
      final title = s.label.trim().isEmpty
          ? (s is NoteSource ? 'Untitled note' : 'Untitled')
          : s.label.trim();
      ChatSourceRef unreadable(String why) =>
          ref(n, s, title, ChatSourceStatus.unreadable, why);

      switch (s) {
        case TextSource(:final text) || NoteSource(markdown: final text):
          if (text.trim().isEmpty) {
            refs.add(unreadable('it is empty'));
          } else {
            texts[n] = text.trim();
            refs.add(ref(n, s, title));
          }
        case FileSource():
          final kind = s.kind;
          if (kind == null) {
            refs.add(unreadable('unsupported file type'));
            continue;
          }
          if (kind == AiInputKind.text) {
            String? text;
            try {
              text = TextExtractor.extract(s.name, s.mimeType, s.bytes);
            } on AppException {
              text = null;
            }
            if (text == null || text.trim().isEmpty) {
              refs.add(unreadable('no readable text'));
            } else {
              texts[n] = text.trim();
              refs.add(ref(n, s, title));
            }
            continue;
          }
          final mime = s.effectiveMimeType;
          final size = s.bytes.length;
          final maxFile =
              kind == AiInputKind.image && limits.maxImageBytes != null
              ? limits.maxImageBytes!
              : limits.maxFileBytes;
          final maxTotal = limits.maxTotalBytes;
          if (!caps.supports(kind) || !limits.kinds.contains(kind)) {
            refs.add(unreadable("$who can't read ${kind.plural}"));
          } else if (kind == AiInputKind.image &&
              limits.imageMimeTypes != null &&
              !limits.imageMimeTypes!.contains(mime)) {
            refs.add(unreadable("$who can't read $mime images"));
          } else if (size > maxFile) {
            refs.add(
              unreadable(
                'too large (${formatBytes(size)}; limit '
                '${formatBytes(maxFile)})',
              ),
            );
          } else if (maxTotal != null && attachedBytes + size > maxTotal) {
            refs.add(
              unreadable(
                'the attached files together exceed ${formatBytes(maxTotal)}',
              ),
            );
          } else {
            final r = ref(n, s, title);
            attachedBytes += size;
            attachments.add(
              LlmFileAttachment(
                label: ChatPrompts.label(r),
                filename: s.name,
                mimeType: mime,
                bytes: s.bytes,
                kind: kind,
              ),
            );
            attached.add(n);
            refs.add(r);
          }
        case YoutubeSource():
          final url = YoutubeUrl.normalize(s.url.trim());
          if (url == null) {
            refs.add(unreadable('not a valid YouTube link'));
          } else if (caps.youtubeNative) {
            final r = ref(n, s, title);
            attachments.add(
              LlmYoutubeAttachment(label: ChatPrompts.label(r), url: url),
            );
            attached.add(n);
            refs.add(r);
          } else if (!caps.youtube) {
            refs.add(
              unreadable(
                "YouTube captions can't be loaded in the browser and "
                '${id.displayName} cannot watch videos',
              ),
            );
          } else {
            try {
              final transcript = await transcripts.fetchTranscript(url);
              texts[n] = transcript.text.trim();
              refs.add(
                ref(
                  n,
                  s,
                  s.title ?? transcript.title ?? title,
                  ChatSourceStatus.full,
                  transcript.isAutoGenerated ? 'auto-generated captions' : null,
                ),
              );
            } on AppException catch (e) {
              refs.add(unreadable(e.message));
            }
          }
      }
    }

    // Fit the text sources into the budget, in priority (list) order.
    final textNumbers = texts.keys.toList()..sort();
    final alloc = allocateTextBudget(
      [for (final n in textNumbers) texts[n]!.length],
      maxContextChars,
      minExcerptChars,
    );
    for (var k = 0; k < textNumbers.length; k++) {
      final n = textNumbers[k];
      final full = texts[n]!;
      final allowed = alloc[k];
      if (allowed >= full.length) continue;
      final i = refs.indexWhere((r) => r.number == n);
      final r = refs[i];
      if (allowed <= 0) {
        texts.remove(n);
        refs[i] = ChatSourceRef(
          number: r.number,
          type: r.type,
          id: r.id,
          title: r.title,
          status: ChatSourceStatus.omitted,
          note: 'left out: too much material for one message',
        );
      } else {
        texts[n] = excerptText(full, allowed);
        refs[i] = ChatSourceRef(
          number: r.number,
          type: r.type,
          id: r.id,
          title: r.title,
          status: ChatSourceStatus.excerpt,
          note:
              'shortened to about ${(allowed * 100 / full.length).round()}% '
              'to fit',
        );
      }
    }
    return PreparedSources(
      sources: refs,
      texts: texts,
      attachments: attachments,
      attached: attached,
    );
  }
}

/// Context sources ready for a prompt.
class PreparedSources {
  const PreparedSources({
    required this.sources,
    required this.texts,
    required this.attachments,
    required this.attached,
  });

  /// Every source, numbered, with its status.
  final List<ChatSourceRef> sources;

  /// Prompt text per source number (full or excerpt).
  final Map<int, String> texts;

  /// Files / YouTube URLs to send, labelled `[S#] file "name"`.
  final List<LlmAttachment> attachments;

  /// Source numbers sent as [attachments].
  final Set<int> attached;

  /// The numbered source block for a prompt (see
  /// [ChatPrompts.sourcesBlock]); empty when there are no sources.
  String get promptBlock => ChatPrompts.sourcesBlock(
    sources: sources,
    texts: texts,
    attached: attached,
  );
}
