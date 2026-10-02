import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../ai/ai_chat_service.dart' as ai;
import '../../../ai/ai_service.dart' show AiSelection;
import '../../../ai/llm_provider.dart';
import '../../../data/models/chat.dart';
import '../../../data/repositories/chat_repository.dart';
import 'chat_format.dart';
import 'chat_sources.dart';

/// Builds the context for the next request (sources + citation types).
typedef ChatContextBuilder = Future<ChatContextSources> Function();

/// Provider / model to answer with (from AI readiness).
typedef ChatModelSelection = ({LlmProviderId? provider, String? model});

/// Drives one chat conversation: sends messages, streams the answer into a
/// local draft message, stops, retries and finalizes via [ChatRepository].
///
/// While streaming, [streamingMessageId] / [streamingText] hold the live
/// answer (the stored draft is updated locally with coalesced writes); the
/// message is finalized (one sync upsert) on completion. Stopping keeps
/// the partial answer with a "stopped" marker ([kStoppedSuffix]).
class ChatSession extends ChangeNotifier {
  ChatSession({
    required this.chatId,
    required this.repository,
    required this.service,
    required this.buildContext,
    required this.selection,
  });

  final String chatId;
  final ChatRepository repository;
  final ai.AiChatService service;
  final ChatContextBuilder buildContext;
  final ChatModelSelection Function() selection;

  bool _busy = false;
  bool _disposed = false;
  Object? _error;
  ChatMessage? _draft;
  String _text = '';
  List<ai.ChatSourceRef> _sources = const [];
  List<ai.ChatSourceRef> _lastSources = const [];
  Map<String, String> _typeById = const {};
  // Cancelled by stop() / dispose(); cleared when the stream ends.
  // ignore: cancel_subscriptions
  StreamSubscription<ai.ChatDelta>? _sub;
  Completer<void>? _done;
  Future<void> _writes = Future.value();
  bool _writeQueued = false;

  /// Preparing or streaming an answer.
  bool get busy => _busy;

  /// The last request's error (cleared by the next send / [clearError]).
  Object? get error => _error;

  /// Id of the assistant message being streamed.
  String? get streamingMessageId => _draft?.id;

  /// Answer text received so far.
  String get streamingText => _text;

  /// Live citations of [streamingText].
  List<ChatCitation> get streamingCitations =>
      storedCitations(ai.ChatCitations.parse(_text, _sources), _typeById);

  /// How the sources of the latest request were used (omitted /
  /// unreadable notices).
  List<ai.ChatSourceRef> get lastSources => _lastSources;

  void clearError() {
    _error = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Sends [text] as a user message and streams the answer.
  Future<void> send(String text) async {
    final message = text.trim();
    if (message.isEmpty || _busy) return;
    _busy = true;
    _error = null;
    _notify();
    try {
      final history = _turns(await repository.getMessages(chatId));
      await repository.addMessage(
        chatId: chatId,
        role: ChatRole.user,
        content: message,
      );
      await _answer(message, history);
    } catch (e) {
      _error = e;
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// Regenerates the answer to the last user message (the previous answer,
  /// if any, is deleted).
  Future<void> retry() async {
    if (_busy) return;
    _busy = true;
    _error = null;
    _notify();
    try {
      final messages = await repository.getMessages(chatId);
      final lastUser = messages.lastIndexWhere((m) => m.role == ChatRole.user);
      if (lastUser < 0) return;
      for (final m in messages.skip(lastUser + 1)) {
        await repository.deleteMessage(m.id);
      }
      await _answer(
        messages[lastUser].content,
        _turns(messages.take(lastUser)),
      );
    } catch (e) {
      _error = e;
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// Stops the answer being streamed; the partial text is kept.
  Future<void> stop() async {
    final sub = _sub;
    if (sub == null) return;
    _sub = null;
    // Not awaited: no further events are delivered after cancel(), and the
    // HTTP abort may take a moment.
    unawaited(sub.cancel());
    await _finishPartial();
    final done = _done;
    if (done != null && !done.isCompleted) done.complete();
  }

  static List<ai.ChatTurn> _turns(Iterable<ChatMessage> messages) => [
    for (final m in messages)
      if (m.role != ChatRole.system && messageBody(m).trim().isNotEmpty)
        ai.ChatTurn(
          role: m.role == ChatRole.user
              ? ai.ChatRole.user
              : ai.ChatRole.assistant,
          text: messageBody(m),
        ),
  ];

  Future<void> _answer(String userMessage, List<ai.ChatTurn> history) async {
    final context = await buildContext();
    _typeById = context.typeById;
    final model = selection();
    _text = '';
    _sources = const [];
    _draft = await repository.addMessage(
      chatId: chatId,
      role: ChatRole.assistant,
      draft: true,
    );
    _notify();
    final done = _done = Completer<void>();
    _sub = service
        .send(
          history: history,
          userMessage: userMessage,
          context: context.sources,
          providerId: model.provider,
          model: model.model,
        )
        .listen(
          (delta) {
            switch (delta) {
              case ai.ChatStarted(:final sources, :final selection):
                _sources = sources;
                _lastSources = sources;
                _saveModel(selection);
                _notify();
              case ai.ChatTextDelta(:final text):
                _text += text;
                _scheduleWrite();
                _notify();
              case ai.ChatCompleted(:final result):
                _sub = null;
                unawaited(_complete(result).whenComplete(done.complete));
            }
          },
          onError: (Object e, StackTrace _) {
            _sub = null;
            _error = e;
            unawaited(_finishPartial().whenComplete(done.complete));
          },
          onDone: () {
            if (_sub != null) {
              // Ended without ChatCompleted: keep what arrived.
              _sub = null;
              unawaited(_finishPartial().whenComplete(done.complete));
            }
          },
          cancelOnError: true,
        );
    await done.future;
  }

  void _saveModel(AiSelection used) {
    unawaited(() async {
      try {
        final chat = await repository.getById(chatId);
        if (chat == null) return;
        if (chat.provider == used.providerId.wireName &&
            chat.model == used.model) {
          return;
        }
        await repository.setModel(
          chatId,
          provider: used.providerId.wireName,
          model: used.model,
        );
      } catch (_) {
        // Best effort.
      }
    }());
  }

  /// Coalesced local (non-finalized) write of the streamed text.
  void _scheduleWrite() {
    if (_writeQueued) return;
    _writeQueued = true;
    _writes = _writes.then((_) async {
      _writeQueued = false;
      final draft = _draft;
      if (draft == null) return;
      try {
        _draft = await repository.updateMessage(
          draft.copyWith(content: _text),
          finalize: false,
        );
      } catch (_) {
        // The final write reports problems.
      }
    });
  }

  Future<void> _complete(ai.ChatResult result) async {
    await _writes;
    final draft = _draft;
    if (draft == null) return;
    try {
      await repository.updateMessage(
        draft.copyWith(
          content: result.text + (result.truncated ? kCutOffSuffix : ''),
          citations: storedCitations(result.citations, _typeById),
        ),
      );
    } catch (e) {
      _error = e;
    } finally {
      _reset();
    }
  }

  /// Finalizes a stopped / failed answer: keeps partial text with the
  /// stopped marker, or deletes the empty draft.
  Future<void> _finishPartial() async {
    await _writes;
    final draft = _draft;
    if (draft == null) return;
    final text = _text;
    final citations = streamingCitations;
    try {
      if (text.trim().isEmpty) {
        await repository.deleteMessage(draft.id);
      } else {
        await repository.updateMessage(
          draft.copyWith(content: text + kStoppedSuffix, citations: citations),
        );
      }
    } catch (e) {
      _error ??= e;
    } finally {
      _reset();
    }
  }

  void _reset() {
    _draft = null;
    _text = '';
    _sources = const [];
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    // Leaving mid-answer stops it and keeps the partial text.
    unawaited(stop());
    super.dispose();
  }
}
