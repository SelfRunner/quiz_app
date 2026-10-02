import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
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

/// Builds a minimal .docx (zip with word/document.xml) in memory.
Uint8List buildDocx(String bodyXml) {
  final xml =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/'
      'wordprocessingml/2006/main"><w:body>$bodyXml</w:body></w:document>';
  final contentTypes = utf8.encode(
    '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.'
    'openxmlformats.org/package/2006/content-types"/>',
  );
  final doc = utf8.encode(xml);
  final archive = Archive()
    ..addFile(
      ArchiveFile('[Content_Types].xml', contentTypes.length, contentTypes),
    )
    ..addFile(ArchiveFile('word/document.xml', doc.length, doc));
  return ZipEncoder().encodeBytes(archive);
}
