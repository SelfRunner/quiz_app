import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/data/models/models.dart';

import 'support/test_db.dart';

Subject _subject(String id, {String owner = 'user-a', DateTime? deletedAt}) {
  final t = DateTime.utc(2026);
  return Subject(
    id: id,
    ownerId: owner,
    title: id,
    createdAt: t,
    updatedAt: t,
    deletedAt: deletedAt,
  );
}

void main() {
  final h = TestHive();
  setUp(h.setUp);
  tearDown(h.tearDown);

  group('Outbox', () {
    test('orders ops FIFO even with a frozen clock', () async {
      h.clock.frozen = true;
      final outbox = h.db.outbox;
      await outbox.enqueueUpsert('subjects', 'b', {'id': 'b'});
      await outbox.enqueueUpsert('subjects', 'a', {'id': 'a'});
      await outbox.enqueueUpsert('notes', 'c', {'id': 'c'});
      expect(outbox.pending().map((o) => o.rowId), ['b', 'a', 'c']);
      final times = outbox.pending().map((o) => o.createdAt).toList();
      expect(times[0].isBefore(times[1]), isTrue);
      expect(times[1].isBefore(times[2]), isTrue);
    });

    test('coalesces upserts of the same row in place', () async {
      final outbox = h.db.outbox;
      await outbox.enqueueUpsert('subjects', 's1', {'id': 's1', 'title': 'A'});
      await outbox.enqueueUpsert('notes', 'n1', {'id': 'n1'});
      await outbox.enqueueUpsert('subjects', 's1', {'id': 's1', 'title': 'B'});
      final ops = outbox.pending();
      expect(ops, hasLength(2));
      expect(ops.first.rowId, 's1'); // keeps its original position
      expect(ops.first.payload!['title'], 'B');
      expect(ops.last.rowId, 'n1');
    });

    test('does not coalesce image ops or different tables', () async {
      final outbox = h.db.outbox;
      await outbox.enqueueUpsert('subjects', 'x', {'id': 'x'});
      await outbox.enqueueUpsert('notes', 'x', {'id': 'x'});
      await outbox.enqueue(
        table: SyncTables.noteImagesBucket,
        op: OutboxOpType.uploadImage,
        rowId: 'p',
      );
      await outbox.enqueue(
        table: SyncTables.noteImagesBucket,
        op: OutboxOpType.deleteImage,
        rowId: 'p',
      );
      expect(outbox.length, 4);
    });

    test('complete() keeps an op that was coalesced while in flight', () async {
      final outbox = h.db.outbox;
      final op = await outbox.enqueueUpsert('subjects', 's1', {'v': 1});
      // Simulate an edit while the op is being pushed.
      await outbox.enqueueUpsert('subjects', 's1', {'v': 2});
      expect(await outbox.complete(op), isFalse);
      expect(outbox.pending().single.payload, {'v': 2});
      expect(await outbox.complete(outbox.pending().single), isTrue);
      expect(outbox.length, 0);
    });

    test('recordFailure increments attempts and stores the error', () async {
      final outbox = h.db.outbox;
      final op = await outbox.enqueueUpsert('subjects', 's1', {'v': 1});
      final failed = await outbox.recordFailure(op, 'boom');
      expect(failed.attempts, 1);
      expect(outbox.pending().single.lastError, 'boom');
      // A new edit resets the retry state.
      await outbox.enqueueUpsert('subjects', 's1', {'v': 2});
      expect(outbox.pending().single.attempts, 0);
    });
  });

  group('LocalTable', () {
    test('watch streams exclude tombstones and re-emit on change', () async {
      final table = h.db.subjects;
      await table.put(_subject('a'));
      final emissions = <List<String>>[];
      final sub = table
          .watchWhere((_) => true, compare: (x, y) => x.id.compareTo(y.id))
          .listen((rows) => emissions.add(rows.map((r) => r.id).toList()));
      await pumpEventQueue();
      await table.put(_subject('b'));
      await pumpEventQueue();
      await table.put(_subject('a', deletedAt: DateTime.utc(2026, 2)));
      await pumpEventQueue();
      await sub.cancel();
      expect(emissions, [
        ['a'],
        ['a', 'b'],
        ['b'],
      ]);
      // Tombstone kept for sync.
      expect(table.get('a')!.isDeleted, isTrue);
      expect(table.getLive('a'), isNull);
    });

    test('watchById emits null for deleted rows', () async {
      final table = h.db.subjects;
      await table.put(_subject('a'));
      final values = <String?>[];
      final sub = table.watchById('a').listen((s) => values.add(s?.id));
      await pumpEventQueue();
      await table.put(_subject('a', deletedAt: DateTime.utc(2026, 2)));
      await pumpEventQueue();
      await sub.cancel();
      expect(values, ['a', null]);
    });
  });
}
