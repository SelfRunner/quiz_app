import 'dart:typed_data';

import 'package:hive_ce/hive_ce.dart';

import '../../core/utils/clock.dart';
import '../models/models.dart';
import 'hive_boxes.dart';
import 'image_cache.dart';
import 'local_table.dart';
import 'outbox.dart';
import 'sync_meta_store.dart';

/// All local (Hive) data sources of the signed-in user.
///
/// Entity tables contain own rows and rows shared with the user (pulled by
/// sync), including tombstones (`deleted_at != null`) of own rows, which are
/// kept for sync and hidden from UI streams.
class LocalDatabase {
  LocalDatabase({
    required Box<String> subjectsBox,
    required Box<String> notesBox,
    required Box<String> quizzesBox,
    required Box<String> attemptsBox,
    required Box<String> outboxBox,
    required Box<String> syncMetaBox,
    required this.images,
    required Clock clock,
    required IdGenerator newId,
  }) : subjects = LocalTable<Subject>(
         name: SyncTables.subjects,
         box: subjectsBox,
         fromJson: Subject.fromJson,
       ),
       notes = LocalTable<Note>(
         name: SyncTables.notes,
         box: notesBox,
         fromJson: Note.fromJson,
       ),
       quizzes = LocalTable<Quiz>(
         name: SyncTables.quizzes,
         box: quizzesBox,
         fromJson: Quiz.fromJson,
       ),
       attempts = LocalTable<QuizAttempt>(
         name: SyncTables.quizAttempts,
         box: attemptsBox,
         fromJson: QuizAttempt.fromJson,
       ),
       outbox = Outbox(outboxBox, clock: clock, newId: newId),
       meta = SyncMetaStore(syncMetaBox);

  /// Uses the boxes opened by [HiveBoxes.init].
  factory LocalDatabase.fromOpenBoxes({
    required Clock clock,
    required IdGenerator newId,
    LocalImageCache? images,
  }) => LocalDatabase(
    subjectsBox: HiveBoxes.box(HiveBoxes.subjects),
    notesBox: HiveBoxes.box(HiveBoxes.notes),
    quizzesBox: HiveBoxes.box(HiveBoxes.quizzes),
    attemptsBox: HiveBoxes.box(HiveBoxes.quizAttempts),
    outboxBox: HiveBoxes.box(HiveBoxes.outbox),
    syncMetaBox: HiveBoxes.box(HiveBoxes.syncMeta),
    images:
        images ??
        createPlatformImageCache(Hive.box<Uint8List>(HiveBoxes.noteImageBytes)),
    clock: clock,
    newId: newId,
  );

  final LocalTable<Subject> subjects;
  final LocalTable<Note> notes;
  final LocalTable<Quiz> quizzes;
  final LocalTable<QuizAttempt> attempts;
  final Outbox outbox;
  final SyncMetaStore meta;
  final LocalImageCache images;

  /// Synced tables in dependency order (`SyncTables.synced`).
  List<LocalTable<Syncable>> get tables => [subjects, notes, quizzes, attempts];

  LocalTable<Syncable> table(String name) => switch (name) {
    SyncTables.subjects => subjects,
    SyncTables.notes => notes,
    SyncTables.quizzes => quizzes,
    SyncTables.quizAttempts => attempts,
    _ => throw ArgumentError.value(name, 'name', 'Not a synced table'),
  };

  /// Writes [row] locally and queues its upsert. The op is enqueued first so
  /// a concurrent pull never overwrites the newer local row.
  Future<void> saveAndEnqueue<T extends Syncable>(
    LocalTable<T> table,
    T row,
  ) async {
    await outbox.enqueueUpsert(table.name, row.id, row.toJson());
    await table.put(row);
  }

  /// Wipes everything user-scoped (sign-out / account switch). Device prefs
  /// are kept.
  Future<void> clearUserData() async {
    for (final t in tables) {
      await t.clear();
    }
    await outbox.clear();
    await meta.clear();
    await images.clear();
  }
}
