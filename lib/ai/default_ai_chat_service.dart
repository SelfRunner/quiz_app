import 'dart:async';

import '../core/errors/app_exception.dart';
import 'ai_chat_service.dart';
import 'ai_service.dart';
import 'chat_context.dart';
import 'llm_chat.dart';
import 'llm_provider.dart';
import 'llm_resolver.dart';
import 'source_context.dart';
import 'transcript_service.dart';

/// Default [AiChatService]: resolves the provider like generation does,
/// numbers the context sources, fits them into [budget], streams the answer
/// through `LlmChatProvider.streamChat` and parses `[S#]` citations.
class DefaultAiChatService implements AiChatService {
  DefaultAiChatService({
    required this.resolver,
    required TranscriptService transcriptService,
    this.budget = const ChatBudget(),
    this.maxOutputTokens,
  }) : _transcripts = transcriptService;

  final LlmResolver resolver;
  final TranscriptService _transcripts;
  final ChatBudget budget;

  /// Output-token cap per answer (null = provider default).
  final int? maxOutputTokens;

  @override
  Stream<ChatDelta> send({
    required List<ChatTurn> history,
    required String userMessage,
    required List<AiSource> context,
    String? language,
    LlmProviderId? providerId,
    String? model,
  }) {
    late final StreamController<ChatDelta> controller;
    StreamSubscription<LlmChatEvent>? inner;
    var cancelled = false;

    Future<void> run() async {
      try {
        if (userMessage.trim().isEmpty) {
          throw const ValidationException('Type a message first.');
        }
        final resolved = await resolver.resolve(
          providerId: providerId,
          model: model,
        );
        final llm = resolved.provider;
        if (llm is! LlmChatProvider) {
          throw AiException(
            '${resolved.selection.providerId.displayName} does not support '
            'chat in this app.',
            kind: AiErrorKind.unsupported,
          );
        }
        final prepared = await SourceContextBuilder(
          resolver: resolver,
          transcripts: _transcripts,
          maxContextChars: budget.maxContextChars,
          minExcerptChars: budget.minExcerptChars,
        ).build(context, resolved);
        if (cancelled) return;
        final hist = fitHistory(history, budget.maxHistoryChars);
        final messages = [
          ...hist.messages,
          LlmChatMessage.user(
            ChatPrompts.userMessage(
              message: userMessage,
              sourcesBlock: prepared.promptBlock,
            ),
          ),
        ];
        controller.add(
          ChatStarted(selection: resolved.selection, sources: prepared.sources),
        );
        final text = StringBuffer();
        inner = (llm as LlmChatProvider)
            .streamChat(
              messages: messages,
              systemPrompt: ChatPrompts.system(
                language: language,
                hasSources: prepared.sources.isNotEmpty,
              ),
              attachments: prepared.attachments,
              maxOutputTokens: maxOutputTokens,
            )
            .listen(
              (event) {
                switch (event) {
                  case LlmTextDelta(text: final t):
                    text.write(t);
                    controller.add(ChatTextDelta(t));
                  case LlmChatDone():
                    try {
                      controller.add(
                        ChatCompleted(
                          _result(
                            text.toString(),
                            event,
                            resolved.selection,
                            prepared.sources,
                            hist.dropped,
                          ),
                        ),
                      );
                    } catch (e, st) {
                      controller.addError(e, st);
                    }
                    unawaited(controller.close());
                }
              },
              onError: (Object e, StackTrace st) {
                controller.addError(e, st);
                unawaited(controller.close());
              },
              onDone: () {
                if (!controller.isClosed) unawaited(controller.close());
              },
              cancelOnError: true,
            );
      } catch (e, st) {
        if (cancelled) return;
        controller.addError(e, st);
        unawaited(controller.close());
      }
    }

    controller = StreamController<ChatDelta>(
      onListen: () => unawaited(run()),
      onCancel: () {
        cancelled = true;
        return inner?.cancel();
      },
    );
    return controller.stream;
  }

  static ChatResult _result(
    String text,
    LlmChatDone done,
    AiSelection selection,
    List<ChatSourceRef> sources,
    int dropped,
  ) {
    final name = selection.providerId.displayName;
    if (text.trim().isEmpty) {
      throw switch (done.reason) {
        LlmFinishReason.refusal => AiException(
          '$name declined to answer'
          '${done.detail == null || done.detail!.isEmpty ? '.' : ': ${done.detail}'}',
        ),
        LlmFinishReason.blocked => AiException(
          '$name blocked this answer (${done.detail ?? 'safety filter'}). '
          'Try rephrasing your question.',
        ),
        LlmFinishReason.length => AiException(
          '$name ran out of output space before answering. Try a shorter '
          'question or fewer sources.',
          kind: AiErrorKind.invalidOutput,
        ),
        _ => AiException('$name returned an empty answer. Try again.'),
      };
    }
    return ChatResult(
      text: text,
      citations: ChatCitations.parse(text, sources),
      sources: sources,
      selection: selection,
      truncated: done.reason == LlmFinishReason.length,
      streamed: done.streamed,
      droppedHistoryTurns: dropped,
    );
  }
}
