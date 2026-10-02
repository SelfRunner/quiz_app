import 'dart:io';
import 'dart:typed_data';

import 'package:hive_ce/hive_ce.dart';
import 'package:quiz_app/core/utils/clock.dart';
import 'package:quiz_app/data/local/image_cache.dart';
import 'package:quiz_app/data/local/local_database.dart';
import 'package:quiz_app/data/repositories/repository_support.dart';

/// Deterministic clock that advances 1 second per call unless frozen.
class TestClock {
  TestClock([DateTime? start]) : now = start ?? DateTime.utc(2026, 1, 1, 12);

  DateTime now;
  bool frozen = false;

  DateTime call() {
    final value = now;
    if (!frozen) now = now.add(const Duration(seconds: 1));
    return value;
  }
}

/// Sequential ids (`id-1`, `id-2`, ...), valid for sorting/tests.
class TestIds {
  int _n = 0;
  String call() => 'id-${++_n}';
}

/// Hive in a temp directory with fresh boxes per test.
class TestHive {
  late Directory dir;
  late LocalDatabase db;
  final TestClock clock = TestClock();
  final TestIds ids = TestIds();
  String? userId = 'user-a';

  Future<void> setUp() async {
    dir = Directory.systemTemp.createTempSync('quiz_app_test_');
    Hive.init(dir.path);
    db = await openDb();
  }

  /// Opens a database; a [suffix] gives a second, independent device
  /// (separate boxes) in the same Hive directory.
  Future<LocalDatabase> openDb({String suffix = ''}) async => LocalDatabase(
    subjectsBox: await Hive.openBox<String>('subjects$suffix'),
    notesBox: await Hive.openBox<String>('notes$suffix'),
    quizzesBox: await Hive.openBox<String>('quizzes$suffix'),
    attemptsBox: await Hive.openBox<String>('quiz_attempts$suffix'),
    attachmentsBox: await Hive.openBox<String>('attachments$suffix'),
    decksBox: await Hive.openBox<String>('decks$suffix'),
    cardReviewsBox: await Hive.openBox<String>('card_reviews$suffix'),
    mistakesBox: await Hive.openBox<String>('mistakes$suffix'),
    outboxBox: await Hive.openBox<String>('outbox$suffix'),
    syncMetaBox: await Hive.openBox<String>('sync_meta$suffix'),
    images: HiveImageCache(
      await Hive.openBox<Uint8List>('note_image_bytes$suffix'),
    ),
    attachmentFiles: LazyHiveBlobCache(
      await Hive.openLazyBox<Uint8List>('attachment_bytes$suffix'),
    ),
    clock: clock.call,
    newId: ids.call,
  );

  DataContext context() => DataContext(
    db: db,
    clock: clock.call,
    newId: ids.call,
    currentUserId: () => userId,
  );

  Clock get clockFn => clock.call;

  Future<void> tearDown() async {
    await Hive.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}

/// Polls [condition] until true (real timers), failing after [timeout].
Future<void> eventually(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
