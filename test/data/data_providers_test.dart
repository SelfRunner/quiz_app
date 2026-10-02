import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/core/providers.dart';
import 'package:quiz_app/data/data_providers.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/data/repositories/attachment_repository.dart';
import 'package:quiz_app/data/repositories/auth_repository.dart';
import 'package:quiz_app/data/sync/connectivity_monitor.dart';
import 'package:quiz_app/data/sync/default_sync_engine.dart';
import 'package:quiz_app/data/sync/sync_engine.dart';

import 'support/fake_remote.dart';
import 'support/test_db.dart';

class _FakeAuth implements AuthRepository {
  final StreamController<AppUser?> changes =
      StreamController<AppUser?>.broadcast();
  AppUser? user = const AppUser(id: 'user-a');

  @override
  AppUser? get currentUser => user;

  @override
  Stream<AppUser?> authStateChanges() async* {
    yield user;
    yield* changes.stream;
  }

  @override
  Future<void> resetPassword(String email) async {}

  @override
  Future<void> signIn({required String email, required String password}) =>
      throw UnimplementedError();

  @override
  Future<void> signOut() async {
    user = null;
    changes.add(null);
  }

  @override
  Future<void> signUp({
    required String email,
    required String password,
    String? displayName,
  }) => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final h = TestHive();
  setUp(h.setUp);
  tearDown(h.tearDown);

  test(
    'providers wire repositories, sync engine and sign-out clearing',
    () async {
      final remote = FakeRemote(userId: 'user-a');
      final auth = _FakeAuth();
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          localDatabaseProvider.overrideWithValue(h.db),
          syncRemoteDataSourceProvider.overrideWithValue(remote),
          imageRemoteDataSourceProvider.overrideWithValue(remote),
          shareRemoteDataSourceProvider.overrideWithValue(remote),
          connectivityMonitorProvider.overrideWithValue(
            const AlwaysOnlineMonitor(),
          ),
          clockProvider.overrideWithValue(h.clockFn),
        ],
      );
      addTearDown(container.dispose);

      final subject = await container
          .read(subjectRepositoryProvider)
          .create(title: 'Wired');
      final engine = container.read(syncEngineProvider);
      expect(engine, isA<DefaultSyncEngine>());
      await engine.sync();
      expect(remote.tables['subjects']!.containsKey(subject.id), isTrue);
      expect(engine.currentStatus.state, SyncState.idle);

      // The auth stream emitting null (e.g. session expired) keeps data ...
      await auth.signOut();
      await pumpEventQueue();
      await (engine as DefaultSyncEngine).authSettled;
      expect(h.db.subjects.all(), hasLength(1));
      // ... an explicit sign-out (SupabaseAuthRepository.afterSignOut) wipes.
      await engine.clearAfterSignOut();
      expect(h.db.subjects.all(), isEmpty);
      await auth.changes.close();
    },
  );

  test('attachment and note-picker providers', () async {
    final remote = FakeRemote(userId: 'user-a');
    final auth = _FakeAuth();
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        localDatabaseProvider.overrideWithValue(h.db),
        syncRemoteDataSourceProvider.overrideWithValue(remote),
        imageRemoteDataSourceProvider.overrideWithValue(remote),
        shareRemoteDataSourceProvider.overrideWithValue(remote),
        connectivityMonitorProvider.overrideWithValue(
          const AlwaysOnlineMonitor(),
        ),
        clockProvider.overrideWithValue(h.clockFn),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(auth.changes.close);

    final subject = await container
        .read(subjectRepositoryProvider)
        .create(title: 'Bio');
    await container
        .read(noteRepositoryProvider)
        .create(subjectId: subject.id, title: 'Cells', contentMd: 'Mitosis');
    final file = await container
        .read(attachmentRepositoryProvider)
        .add(
          subjectId: subject.id,
          name: 'slides.pdf',
          bytes: Uint8List.fromList([1]),
        );

    Future<T> first<T>(ProviderListenable<AsyncValue<T>> p) async {
      final completer = Completer<T>();
      final sub = container.listen(p, (_, next) {
        if (next.hasValue && !completer.isCompleted) {
          completer.complete(next.value as T);
        }
      }, fireImmediately: true);
      final value = await completer.future;
      sub.close();
      return value;
    }

    expect(await first(attachmentsForSubjectProvider(subject.id)), [file]);
    expect(await first(accessibleAttachmentsProvider), [file]);
    expect(await first(attachmentProvider(file.id)), file);
    expect(
      (await first(attachmentUploadProvider(file.id))).phase,
      AttachmentUploadPhase.queued,
    );
    expect(await first(accessibleNotesProvider), hasLength(1));
    expect(await first(noteSearchProvider('MITOSIS')), hasLength(1));
    expect(await first(noteSearchProvider('nothing')), isEmpty);

    await container.read(syncEngineProvider).sync();
    expect(remote.attachmentObjects.keys, [file.storagePath]);
    expect(
      await first(attachmentUploadProvider(file.id)),
      AttachmentUploadState.done,
    );
  });
}
