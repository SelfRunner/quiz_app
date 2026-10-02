import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

@JS('Blob')
extension type _Blob._(JSObject _) implements JSObject {
  external factory _Blob(JSArray<JSAny> parts, JSObject options);
}

@JS('URL.createObjectURL')
external String _createObjectUrl(JSObject blob);

@JS('URL.revokeObjectURL')
external void _revokeObjectUrl(String url);

@JS('document.createElement')
external JSObject _createElement(String tag);

@JS('document.body')
external JSObject get _body;

/// Triggers a browser download of [bytes] via a temporary object URL.
Future<String?> saveFileBytes(
  String fileName,
  Uint8List bytes,
  String? mimeType,
) async {
  final options = JSObject()
    ..setProperty('type'.toJS, (mimeType ?? 'application/octet-stream').toJS);
  final blob = _Blob(<JSAny>[bytes.toJS].toJS, options);
  final url = _createObjectUrl(blob);
  final anchor = _createElement('a')
    ..setProperty('href'.toJS, url.toJS)
    ..setProperty('download'.toJS, fileName.toJS)
    ..setProperty('rel'.toJS, 'noopener'.toJS);
  _body.callMethod<JSAny?>('appendChild'.toJS, anchor);
  anchor
    ..callMethod<JSAny?>('click'.toJS)
    ..callMethod<JSAny?>('remove'.toJS);
  Timer(const Duration(minutes: 1), () => _revokeObjectUrl(url));
  return null;
}
