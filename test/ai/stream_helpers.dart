import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// `data: <json>\n\n` (optionally with an `event:` line).
String sse(Object data, {String? event}) =>
    '${event == null ? '' : 'event: $event\n'}'
    'data: ${data is String ? data : jsonEncode(data)}\n\n';

/// UTF-8 bytes of [body] in chunks of [size] bytes (splits multi-byte
/// characters and line endings across chunks).
List<List<int>> byteChunks(String body, int size) {
  final bytes = utf8.encode(body);
  return [
    for (var i = 0; i < bytes.length; i += size)
      bytes.sublist(i, i + size > bytes.length ? bytes.length : i + size),
  ];
}

/// A recorded streaming request.
class StreamCall {
  StreamCall(this.request, this.body);
  final http.BaseRequest request;
  final String body;

  Uri get url => request.url;
  Map<String, String> get headers => request.headers;
  Map<String, dynamic> get json => jsonDecode(body) as Map<String, dynamic>;

  /// The abort trigger of an `http.Abortable` request (null otherwise).
  Future<void>? get abortTrigger => request is http.Abortable
      ? (request as http.Abortable).abortTrigger
      : null;
}

/// One canned response for [StreamingClient].
class StreamReply {
  StreamReply.sse(String body, {this.chunkSize = 7, this.status = 200})
    : chunks = byteChunks(body, chunkSize),
      contentType = 'text/event-stream',
      controller = null;

  StreamReply.json(Object body, {this.status = 200})
    : chunks = [utf8.encode(jsonEncode(body))],
      chunkSize = 0,
      contentType = 'application/json',
      controller = null;

  /// Body driven by the test (for cancellation tests).
  StreamReply.controlled(StreamController<List<int>> this.controller)
    : chunks = const [],
      chunkSize = 0,
      status = 200,
      contentType = 'text/event-stream';

  final List<List<int>> chunks;
  final int chunkSize;
  final int status;
  final String contentType;
  final StreamController<List<int>>? controller;
}

/// MockClient.streaming that records requests and answers from a queue of
/// replies (the last one repeats).
class StreamingClient {
  StreamingClient(this.replies);

  final List<StreamReply> replies;
  final calls = <StreamCall>[];

  late final http.Client client = MockClient.streaming((request, body) async {
    final text = await body.bytesToString();
    calls.add(StreamCall(request, text));
    final i = calls.length - 1;
    final reply = replies[i < replies.length ? i : replies.length - 1];
    final stream =
        reply.controller?.stream ?? Stream.fromIterable(reply.chunks);
    return http.StreamedResponse(
      stream,
      reply.status,
      headers: {'content-type': reply.contentType},
      request: request,
    );
  });
}
