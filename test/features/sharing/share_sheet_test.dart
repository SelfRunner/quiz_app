import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/core/errors/app_exception.dart';
import 'package:quiz_app/data/models/models.dart';
import 'package:quiz_app/features/sharing/widgets/share_actions.dart';

import 'sharing_fakes.dart';

Widget _opener() => Scaffold(
  body: Builder(
    builder: (context) => Center(
      child: TextButton(
        onPressed: () => showShareSheet(
          context,
          type: ShareResourceType.subject,
          resourceId: 's1',
          title: 'Biology',
        ),
        child: const Text('open'),
      ),
    ),
  ),
);

Future<void> _open(WidgetTester tester, FakeShareRepository repo) async {
  await tester.pumpWidget(harness(home: _opener(), shares: repo));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _submitEmail(WidgetTester tester, String email) async {
  await tester.enterText(
    find.byKey(const ValueKey('share-email-field')),
    email,
  );
  await tester.tap(find.byKey(const ValueKey('share-submit')));
  await tester.pumpAndSettle();
}

void main() {
  late FakeShareRepository repo;

  setUp(() {
    repo = FakeShareRepository()
      ..usersByEmail['bob@example.com'] = profile('bob', name: 'Bob');
  });

  testWidgets('explains access and shows the empty recipients state', (
    tester,
  ) async {
    await _open(tester, repo);
    expect(find.text('Share “Biology”'), findsOneWidget);
    expect(find.textContaining('including ones you add later'), findsOneWidget);
    expect(find.textContaining('Only you can see this'), findsOneWidget);
    // 800 px wide test surface -> dialog.
    expect(find.byType(Dialog), findsOneWidget);
  });

  testWidgets('uses a bottom sheet on phones', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _open(tester, repo);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('shares by email and lists the new recipient', (tester) async {
    await _open(tester, repo);
    await _submitEmail(tester, 'Bob@Example.com ');

    expect(find.text('Shared with Bob.'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.textContaining('bob@example.com'), findsOneWidget);
    expect(repo.sharesByResource['s1'], hasLength(1));
  });

  testWidgets('shows an error when no account matches the email', (
    tester,
  ) async {
    await _open(tester, repo);
    await _submitEmail(tester, 'nobody@example.com');

    expect(find.textContaining('No account found for'), findsOneWidget);
    expect(repo.sharesByResource['s1'], isNull);
  });

  testWidgets('rejects sharing with yourself', (tester) async {
    await _open(tester, repo);
    await _submitEmail(tester, meEmail);
    expect(find.text("You can't share with yourself."), findsOneWidget);

    // Also when the lookup resolves to the current user's id.
    repo.usersByEmail['alias@example.com'] = profile(meId, name: 'Me');
    await _submitEmail(tester, 'alias@example.com');
    expect(find.text("You can't share with yourself."), findsOneWidget);
    expect(repo.sharesByResource['s1'], isNull);
  });

  testWidgets('validates the email format', (tester) async {
    await _open(tester, repo);
    await _submitEmail(tester, 'not-an-email');
    expect(find.text('Enter a valid email address.'), findsOneWidget);
  });

  testWidgets('reports when already shared with that person', (tester) async {
    repo.sharesByResource['s1'] = [
      makeShare(
        id: 'sh1',
        type: ShareResourceType.subject,
        resourceId: 's1',
        ownerId: meId,
        recipientId: 'bob',
        recipient: profile('bob', name: 'Bob'),
      ),
    ];
    await _open(tester, repo);
    await _submitEmail(tester, 'bob@example.com');
    expect(find.text('Already shared with Bob.'), findsOneWidget);
    expect(repo.sharesByResource['s1'], hasLength(1));
  });

  testWidgets('shows an offline state when the list cannot load', (
    tester,
  ) async {
    repo.listError = const NetworkException("You're offline.");
    await _open(tester, repo);
    expect(find.textContaining("You're offline. Connect"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('revokes access after confirmation', (tester) async {
    repo.sharesByResource['s1'] = [
      makeShare(
        id: 'sh1',
        type: ShareResourceType.subject,
        resourceId: 's1',
        ownerId: meId,
        recipientId: 'bob',
        recipient: profile('bob', name: 'Bob'),
      ),
    ];
    await _open(tester, repo);
    expect(find.text('Bob'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove access'));
    await tester.pumpAndSettle();
    expect(find.text('Remove access?'), findsOneWidget);

    // Cancel keeps the share.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.revoked, isEmpty);

    await tester.tap(find.byTooltip('Remove access'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(repo.revoked, ['sh1']);
    expect(find.text('Removed access for Bob.'), findsOneWidget);
    expect(find.textContaining('Only you can see this'), findsOneWidget);
  });
}
