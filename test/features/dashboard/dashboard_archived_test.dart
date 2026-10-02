import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/data/data_providers.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/features/dashboard/application/dashboard_providers.dart';

void main() {
  test('recent notes leave out notes of archived subjects', () async {
    final t = DateTime.utc(2026, 1, 1);
    Note note(String id, String subjectId, int day) => Note(
      id: id,
      subjectId: subjectId,
      ownerId: 'u',
      title: id,
      createdAt: t.add(Duration(days: day)),
      updatedAt: t,
    );
    Subject subject(String id, {bool archived = false}) => Subject(
      id: id,
      ownerId: 'u',
      title: id,
      archivedAt: archived ? t : null,
      createdAt: t,
      updatedAt: t,
    );
    final container = ProviderContainer(
      overrides: [
        currentUserIdProvider.overrideWithValue('u'),
        accessibleNotesProvider.overrideWith(
          (ref) => Stream.value([
            note('a', 'active', 1),
            note('b', 'archived', 2),
            note('c', 'active', 3),
          ]),
        ),
        subjectProvider.overrideWith(
          (ref, id) => Stream.value(subject(id, archived: id == 'archived')),
        ),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(recentNotesProvider, (_, _) {});
    addTearDown(sub.close);
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(container.read(recentNotesProvider).map((n) => n.id), ['c', 'a']);
  });
}
