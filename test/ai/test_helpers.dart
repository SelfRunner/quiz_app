import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A recorded request.
class Captured {
  Captured(this.request);
  final http.Request request;

  Uri get url => request.url;
  String get method => request.method;
  Map<String, String> get headers => request.headers;
  Map<String, dynamic> get json =>
      jsonDecode(request.body) as Map<String, dynamic>;
}

/// MockClient that records requests and answers from a queue of handlers
/// (the last handler repeats).
class RecordingClient {
  RecordingClient(this._handlers);

  final List<http.Response Function(http.Request request)> _handlers;
  final requests = <Captured>[];

  late final MockClient client = MockClient((request) async {
    requests.add(Captured(request));
    final i = requests.length - 1;
    final handler = _handlers[i < _handlers.length ? i : _handlers.length - 1];
    return handler(request);
  });
}

http.Response jsonResponse(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// A valid QuizDraft JSON payload with [n] mcq_single questions.
Map<String, dynamic> validQuizJson({int n = 2}) => {
  'title': 'Cells',
  'description': 'Basics of cells.',
  'questions': [
    for (var i = 0; i < n; i++)
      {
        'type': 'mcq_single',
        'prompt': 'Question $i about organelle number $i?',
        'options': ['A$i', 'B$i', 'C$i'],
        'correct_indices': [1],
        'answer_text': null,
        'explanation': 'Because B$i.',
      },
  ],
};
