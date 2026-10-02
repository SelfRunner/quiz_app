import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/core/errors/app_exception.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/features/sharing/widgets/share_actions.dart';

import 'sharing_fakes.dart';

Widget _home(ShareResourceType type, String id) => Scaffold(
  body: Center(
    child: CopyToAccountButton(type: type, resourceId: id),
  ),
);

void main() {
  late FakeShareRepository shares;
  late FakeSubjectRepository subjects;
  late FakeNoteRepository notes;

  setUp(() {
    shares = FakeShareRepository();
    subjects = FakeSubjectRepository([
      makeSubject('math', 'Math'),
      makeSubject('art', 'Art'),
      makeSubject('theirs', 'Their subject', ownerId: 'alice'),
    ]);
    notes = FakeNoteRepository([makeNote('n1', 'theirs')]);
  });

  Future<void> pump(WidgetTester tester, ShareResourceType type, String id) =>
      tester.pumpWidget(
        harness(
          home: _home(type, id),
          shares: shares,
          subjects: subjects,
          notes: notes,
          quizzes: FakeQuizRepository([makeQuiz('qz1', 'theirs')]),
        ),
      );

  testWidgets('note: picks an owned subject, copies and opens the copy', (
    tester,
  ) async {
    await pump(tester, ShareResourceType.note, 'n1');
    await tester.tap(find.text('Copy to my account'));
    await tester.pumpAndSettle();

    // Only owned subjects are offered, plus "New subject".
    expect(find.text('Copy note to…'), findsOneWidget);
    expect(find.text('Math'), findsOneWidget);
    expect(find.text('Art'), findsOneWidget);
    expect(find.text('Their subject'), findsNothing);
    expect(find.text('New subject'), findsOneWidget);

    await tester.tap(find.text('Math'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('copy-target-confirm')));
    await tester.pumpAndSettle();

    expect(shares.copies, hasLength(1));
    expect(shares.copies.single.type, ShareResourceType.note);
    expect(shares.copies.single.id, 'n1');
    expect(shares.copies.single.subjectId, 'math');
    expect(find.text('Copied “Note n1” to your account.'), findsOneWidget);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('note:copy-1'), findsOneWidget);
  });

  testWidgets('quiz: creates a new subject first when chosen', (tester) async {
    await pump(tester, ShareResourceType.quiz, 'qz1');
    await tester.tap(find.text('Copy to my account'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('New subject'));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('copy-target-new-title'));
    // Suggests the shared item's subject title.
    expect(tester.widget<TextField>(field).controller!.text, 'Their subject');
    await tester.enterText(field, 'Imported');
    await tester.tap(find.byKey(const ValueKey('copy-target-confirm')));
    await tester.pumpAndSettle();

    expect(subjects.created, ['Imported']);
    expect(shares.copies.single.subjectId, 'new-subject');
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('quiz:copy-1'), findsOneWidget);
  });

  testWidgets('cancelling the picker copies nothing', (tester) async {
    await pump(tester, ShareResourceType.note, 'n1');
    await tester.tap(find.text('Copy to my account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(shares.copies, isEmpty);
  });

  testWidgets('subject: confirms, copies without a picker and opens it', (
    tester,
  ) async {
    await pump(tester, ShareResourceType.subject, 'theirs');
    await tester.tap(find.text('Copy to my account'));
    await tester.pumpAndSettle();
    expect(find.text('Copy to my account?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('copy-subject-confirm')));
    await tester.pumpAndSettle();

    expect(shares.copies.single.subjectId, isNull);
    expect(
      find.text('Copied “Their subject” to your account.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('subject:copy-1'), findsOneWidget);
  });

  testWidgets('shows a friendly error when the copy fails', (tester) async {
    shares.copyError = const NetworkException(
      "You're offline. Sharing needs an internet connection.",
    );
    await pump(tester, ShareResourceType.subject, 'theirs');
    await tester.tap(find.text('Copy to my account'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('copy-subject-confirm')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining("Couldn't copy this subject. You're offline."),
      findsOneWidget,
    );
    expect(find.text('Open'), findsNothing);
    // Progress dialog is gone.
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('compact variant renders an icon button', (tester) async {
    await tester.pumpWidget(
      harness(
        home: const Scaffold(
          body: CopyToAccountButton(
            type: ShareResourceType.quiz,
            resourceId: 'qz1',
            compact: true,
          ),
        ),
        shares: shares,
        subjects: subjects,
      ),
    );
    expect(find.byTooltip('Copy to my account'), findsOneWidget);
  });
}
