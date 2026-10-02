import 'dart:async';
import 'dart:convert';

/// One Server-Sent Event.
class SseEvent {
  const SseEvent({required this.data, this.event, this.id});

  /// `event:` field (null = default `message`).
  final String? event;

  /// `data:` lines joined with `\n`.
  final String data;
  final String? id;

  @override
  String toString() => 'SseEvent(${event ?? 'message'}, $data)';
}

/// Decodes a `text/event-stream` byte stream into events (WHATWG SSE rules):
/// UTF-8 split across chunks, `\n` / `\r\n` / `\r` line endings, multi-line
/// `data:`, comment lines (`: keep-alive`) ignored. An event without a
/// trailing blank line at the end of the stream is still delivered
/// (lenient for proxies that drop the last separator).
///
/// Cancelling the returned stream cancels the subscription to [bytes] right
/// away (needed to abort an HTTP response mid-stream).
Stream<SseEvent> parseSse(Stream<List<int>> bytes) {
  late final StreamController<SseEvent> controller;
  StreamSubscription<String>? sub;
  String? event;
  String? id;
  final data = <String>[];
  var hasData = false;

  void dispatch() {
    if (hasData) {
      controller.add(SseEvent(data: data.join('\n'), event: event, id: id));
    }
    data.clear();
    hasData = false;
    event = null;
  }

  void onLine(String line) {
    if (line.isEmpty) {
      dispatch();
      return;
    }
    if (line.startsWith(':')) return;
    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    switch (field) {
      case 'data':
        data.add(value);
        hasData = true;
      case 'event':
        event = value;
      case 'id':
        id = value;
      default:
        // `retry` and unknown fields are ignored.
        break;
    }
  }

  controller = StreamController<SseEvent>(
    onListen: () {
      sub = bytes
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            onLine,
            onError: controller.addError,
            onDone: () {
              dispatch();
              unawaited(controller.close());
            },
          );
    },
    onPause: () => sub?.pause(),
    onResume: () => sub?.resume(),
    onCancel: () => sub?.cancel(),
  );
  return controller.stream;
}
