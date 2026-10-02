import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/misc.dart';
import 'package:quiz_app/data/data_providers.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/data/repositories/attachment_repository.dart';
import 'package:quiz_app/features/ai_generate/data/ai_file_picker.dart';

import '../../quizzes/support/fakes.dart';

/// In-memory subject "Files" library.
class FakeAttachmentRepository implements AttachmentRepository {
  final Map<String, Attachment> rows = {};
  final Map<String, Uint8List> bytes = {};
  final List<Attachment> added = [];
  final List<String> bytesRequested = [];
  final _changes = StreamController<void>.broadcast();

  /// Upload phase reported for every attachment.
  AttachmentUploadPhase uploadPhase = AttachmentUploadPhase.done;

  Attachment put(
    String id,
    String subjectId,
    String name, {
    String owner = userId,
    int size = 1000,
    String? extractedText,
    Uint8List? data,
  }) {
    final a = Attachment(
      id: id,
      subjectId: subjectId,
      ownerId: owner,
      name: name,
      mimeType: mimeTypeForFileName(name),
      sizeBytes: size,
      kind: AttachmentKind.detect(fileName: name),
      storagePath: '$owner/$subjectId/$id/$name',
      extractedText: extractedText,
      createdAt: fixedNow,
      updatedAt: fixedNow,
    );
    rows[id] = a;
    bytes[id] = data ?? Uint8List.fromList([1, 2, 3]);
    _changes.add(null);
    return a;
  }

  Stream<R> _watch<R>(R Function() read) async* {
    yield read();
    yield* _changes.stream.map((_) => read());
  }

  @override
  Stream<List<Attachment>> watchBySubject(String subjectId) =>
      _watch(() => rows.values.where((a) => a.subjectId == subjectId).toList());

  @override
  Stream<List<Attachment>> watchAllAccessible() =>
      _watch(() => rows.values.toList());

  @override
  Stream<Attachment?> watchById(String id) => _watch(() => rows[id]);

  @override
  Future<Attachment?> getById(String id) async => rows[id];

  @override
  Future<Attachment> add({
    required String subjectId,
    required String name,
    String? mimeType,
    required Uint8List bytes,
    String? extractedText,
  }) async {
    final a = put(
      nextId(),
      subjectId,
      name,
      size: bytes.length,
      extractedText: extractedText,
      data: bytes,
    );
    added.add(a);
    return a;
  }

  @override
  Future<Attachment> update(Attachment attachment) async =>
      rows[attachment.id] = attachment;

  @override
  Future<Attachment> rename(String id, String name) async =>
      rows[id] = rows[id]!.copyWith(name: name);

  @override
  Future<void> delete(String id) async {
    rows.remove(id);
    _changes.add(null);
  }

  @override
  Future<Uint8List> getBytes(Attachment attachment) async {
    bytesRequested.add(attachment.id);
    return bytes[attachment.id]!;
  }

  @override
  Future<bool> isCached(Attachment attachment) async => true;

  @override
  Stream<AttachmentUploadState> watchUpload(Attachment attachment) =>
      Stream.value(AttachmentUploadState(uploadPhase));
}

/// Returns [next] on every pick and records the requested extensions.
class FakeFilePicker implements AiFilePicker {
  List<PickedFile> next = [];
  final List<List<String>> requests = [];

  @override
  Future<List<PickedFile>> pick({required List<String> extensions}) async {
    requests.add(extensions);
    return next;
  }
}

/// [TestEnv] plus attachments and the file picker.
class AiTestEnv extends TestEnv {
  final attachments = FakeAttachmentRepository();
  final picker = FakeFilePicker();

  @override
  List<Override> get extraOverrides => [
    attachmentRepositoryProvider.overrideWithValue(attachments),
    aiFilePickerProvider.overrideWithValue(picker),
  ];
}
