import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/core/widgets/design_system.dart';

Widget wrap(Widget child, {ThemeData? theme}) => MaterialApp(
  theme: theme ?? AppTheme.light(),
  home: Scaffold(body: child),
);

Future<void> hover(WidgetTester tester, Finder finder) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(gesture.removePointer);
  await gesture.moveTo(tester.getCenter(finder));
  await tester.pumpAndSettle();
}

void main() {
  group('SectionHeader', () {
    testWidgets('renders title, count and trailing action', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        wrap(
          SectionHeader(
            title: 'Notes',
            count: 4,
            subtitle: 'Recently edited',
            trailing: TextButton(
              onPressed: () => tapped = true,
              child: const Text('New'),
            ),
          ),
        ),
      );
      expect(find.textContaining('Notes'), findsOneWidget);
      expect(find.textContaining('4'), findsOneWidget);
      expect(find.text('Recently edited'), findsOneWidget);
      await tester.tap(find.text('New'));
      expect(tapped, isTrue);
    });
  });

  group('EmptyState', () {
    testWidgets('shows icon, title, message and action', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        wrap(
          EmptyState(
            icon: Icons.note_outlined,
            title: 'No notes yet',
            message: 'Create your first note.',
            action: FilledButton(
              onPressed: () => tapped = true,
              child: const Text('New note'),
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.note_outlined), findsOneWidget);
      expect(find.text('No notes yet'), findsOneWidget);
      expect(find.text('Create your first note.'), findsOneWidget);
      await tester.tap(find.text('New note'));
      expect(tapped, isTrue);
    });

    testWidgets('compact variant renders inline in a column', (tester) async {
      await tester.pumpWidget(
        wrap(
          const Column(
            children: [
              EmptyState(
                icon: Icons.quiz_outlined,
                title: 'No quizzes',
                compact: true,
              ),
            ],
          ),
        ),
      );
      expect(find.text('No quizzes'), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsNothing);
    });

    testWidgets('AsyncValueView uses the custom loading widget', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          AsyncValueView<int>(
            value: const AsyncLoading(),
            data: (v) => Text('$v'),
            loading: const LoadingSkeleton(animate: false),
          ),
        ),
      );
      expect(find.byType(LoadingSkeleton), findsOneWidget);
      await tester.pumpWidget(
        wrap(
          AsyncValueView<int>(
            value: const AsyncData(3),
            data: (v) => Text('value $v'),
          ),
        ),
      );
      expect(find.text('value 3'), findsOneWidget);
    });
  });

  group('AppCard', () {
    testWidgets('tap, accent border and hover border', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        wrap(
          Center(
            child: AppCard(
              accentColor: Colors.teal,
              onTap: () => taps++,
              child: const Text('Biology'),
            ),
          ),
          theme: AppTheme.light().copyWith(platform: TargetPlatform.macOS),
        ),
      );
      final accent = find.byWidgetPredicate(
        (w) => w is ColoredBox && w.color == Colors.teal,
      );
      expect(accent, findsOneWidget);
      expect(tester.getSize(accent).width, AppCard.accentWidth);

      BorderSide side() {
        final material = tester.widget<Material>(
          find
              .descendant(
                of: find.byType(AppCard),
                matching: find.byType(Material),
              )
              .first,
        );
        return (material.shape! as RoundedRectangleBorder).side;
      }

      expect(side().color, AppColors.light.hairline);
      await hover(tester, find.text('Biology'));
      expect(side().color, AppColors.light.border);

      await tester.tap(find.text('Biology'));
      expect(taps, 1);
    });

    testWidgets('non-interactive card has no InkWell', (tester) async {
      await tester.pumpWidget(wrap(const AppCard(child: Text('Static'))));
      expect(
        find.descendant(
          of: find.byType(AppCard),
          matching: find.byType(InkWell),
        ),
        findsNothing,
      );
    });
  });

  group('ListRowTile', () {
    Widget row({required VoidCallback onTap, required VoidCallback onAction}) =>
        ListRowTile(
          leading: const Icon(Icons.description_outlined),
          title: const Text('Cell biology'),
          subtitle: const Text('Edited today'),
          trailing: const Text('3 quizzes'),
          onTap: onTap,
          actions: [
            IconButton(
              tooltip: 'More',
              onPressed: onAction,
              icon: const Icon(Icons.more_horiz),
            ),
          ],
        );

    double actionsOpacity(WidgetTester tester) => tester
        .widget<AnimatedOpacity>(find.byKey(const ValueKey('list-row-actions')))
        .opacity;

    testWidgets('desktop: actions reveal on hover; taps work', (tester) async {
      var taps = 0;
      var actions = 0;
      await tester.pumpWidget(
        wrap(
          row(onTap: () => taps++, onAction: () => actions++),
          theme: AppTheme.light().copyWith(platform: TargetPlatform.macOS),
        ),
      );
      expect(find.text('Cell biology'), findsOneWidget);
      expect(find.text('Edited today'), findsOneWidget);
      expect(find.text('3 quizzes'), findsOneWidget);
      expect(actionsOpacity(tester), 0);

      await hover(tester, find.text('Cell biology'));
      expect(actionsOpacity(tester), 1);

      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.tap(find.text('Cell biology'));
      expect(actions, 1);
      expect(taps, 1);
    });

    testWidgets('touch: actions always visible', (tester) async {
      await tester.pumpWidget(
        wrap(
          row(onTap: () {}, onAction: () {}),
          theme: AppTheme.light().copyWith(platform: TargetPlatform.android),
        ),
      );
      expect(actionsOpacity(tester), 1);
    });
  });

  group('SubjectColorDot', () {
    testWidgets('resolves stored color, fallback and none', (tester) async {
      await tester.pumpWidget(
        wrap(
          const Row(
            children: [
              SubjectColorDot(color: 0xFF00897B, semanticLabel: 'Teal'),
              SubjectColorDot(fallback: Colors.indigo),
              SubjectColorDot(size: 14),
            ],
          ),
        ),
      );
      final dots = tester
          .widgetList<SubjectColorDot>(find.byType(SubjectColorDot))
          .toList();
      expect(dots[0].resolvedColor, const Color(0xFF00897B));
      expect(dots[1].resolvedColor, Colors.indigo);
      expect(dots[2].resolvedColor, isNull);
      expect(
        tester.getSize(find.byType(SubjectColorDot).at(2)),
        const Size(14, 14),
      );
      expect(find.bySemanticsLabel('Teal'), findsOneWidget);
    });
  });

  group('InfoBanner', () {
    testWidgets('renders each kind with its icon', (tester) async {
      await tester.pumpWidget(
        wrap(
          Column(
            children: [
              for (final kind in InfoBannerKind.values)
                InfoBanner(kind: kind, message: kind.name),
            ],
          ),
        ),
      );
      for (final kind in InfoBannerKind.values) {
        expect(find.text(kind.name), findsOneWidget);
        expect(find.byIcon(InfoBanner.defaultIcon(kind)), findsOneWidget);
      }
    });

    testWidgets('action and dismiss', (tester) async {
      var acted = false;
      var dismissed = false;
      await tester.pumpWidget(
        wrap(
          InfoBanner(
            kind: InfoBannerKind.warning,
            title: 'AI not set up',
            message: 'Add a provider key in Settings.',
            action: TextButton(
              onPressed: () => acted = true,
              child: const Text('Open settings'),
            ),
            onDismiss: () => dismissed = true,
          ),
          theme: AppTheme.dark(),
        ),
      );
      expect(find.text('AI not set up'), findsOneWidget);
      await tester.tap(find.text('Open settings'));
      await tester.tap(find.byTooltip('Dismiss'));
      expect(acted, isTrue);
      expect(dismissed, isTrue);
    });
  });

  group('LockedFeature', () {
    testWidgets('locked: child inert, badge shown, onTap called', (
      tester,
    ) async {
      var childTaps = 0;
      var lockedTaps = 0;
      await tester.pumpWidget(
        wrap(
          Center(
            child: LockedFeature(
              tooltip: 'Set up AI to use this',
              onTap: () => lockedTaps++,
              child: FilledButton(
                onPressed: () => childTaps++,
                child: const Text('Generate'),
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(LockedFeature.badgeKey), findsOneWidget);
      expect(find.byIcon(LockedFeature.lockIcon), findsOneWidget);
      final opacity = tester.widget<Opacity>(
        find.ancestor(
          of: find.text('Generate'),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacity.opacity, lessThan(1));

      // The child ignores pointers; the tap lands on the lock wrapper.
      await tester.tap(find.text('Generate'), warnIfMissed: false);
      expect(childTaps, 0);
      expect(lockedTaps, 1);
    });

    testWidgets('unlocked: child works, no badge', (tester) async {
      var childTaps = 0;
      await tester.pumpWidget(
        wrap(
          Center(
            child: LockedFeature(
              locked: false,
              onTap: () => fail('should not be called'),
              child: FilledButton(
                onPressed: () => childTaps++,
                child: const Text('Generate'),
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(LockedFeature.badgeKey), findsNothing);
      await tester.tap(find.text('Generate'));
      expect(childTaps, 1);
    });

    testWidgets('locked feature is keyboard activatable', (tester) async {
      var lockedTaps = 0;
      await tester.pumpWidget(
        wrap(
          Center(
            child: LockedFeature(
              onTap: () => lockedTaps++,
              child: const Text('AI'),
            ),
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(lockedTaps, 1);
    });
  });

  group('layout', () {
    testWidgets('ContentContainer caps width and centers', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const ResponsiveScaffold(
            body: SizedBox(
              key: Key('body'),
              height: 100,
              width: double.infinity,
            ),
          ),
        ),
      );
      final size = tester.getSize(find.byKey(const Key('body')));
      expect(size.width, ContentWidth.readable - 2 * Insets.gutterWide);
      final left = tester.getTopLeft(find.byKey(const Key('body'))).dx;
      expect(left, (1400 - ContentWidth.readable) / 2 + Insets.gutterWide);
    });

    testWidgets('ResponsiveScaffold scrollable on a phone', (tester) async {
      tester.view.physicalSize = const Size(390, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: ResponsiveScaffold(
            appBar: AppBar(title: const Text('Settings')),
            maxWidth: ContentWidth.form,
            scrollable: true,
            body: const Column(
              children: [
                SizedBox(
                  key: Key('tall'),
                  height: 2000,
                  width: double.infinity,
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('tall'))).width,
        390 - 2 * Insets.gutter,
      );
      expect(
        Breakpoints.isMedium(tester.element(find.text('Settings'))),
        isFalse,
      );
    });
  });

  group('KeyboardShortcutHint', () {
    test('keysFor is platform aware', () {
      const save = SingleActivator(LogicalKeyboardKey.keyS, control: true);
      const mSave = SingleActivator(
        LogicalKeyboardKey.keyS,
        meta: true,
        shift: true,
      );
      expect(KeyboardShortcutHint.keysFor(save, TargetPlatform.windows), [
        'Ctrl',
        'S',
      ]);
      expect(KeyboardShortcutHint.keysFor(mSave, TargetPlatform.macOS), [
        '⌘',
        '⇧',
        'S',
      ]);
    });

    testWidgets('renders keycaps and label', (tester) async {
      await tester.pumpWidget(
        wrap(
          const Column(
            children: [
              KeyboardShortcutHint(keys: ['Ctrl', 'K'], label: 'Search'),
              KeyboardShortcutHint.activator(
                SingleActivator(LogicalKeyboardKey.enter, control: true),
              ),
            ],
          ),
          theme: AppTheme.light().copyWith(platform: TargetPlatform.linux),
        ),
      );
      expect(find.text('Search'), findsOneWidget);
      expect(find.text('Ctrl'), findsNWidgets(2));
      expect(find.text('K'), findsOneWidget);
      expect(find.text('Enter'), findsOneWidget);
      expect(find.bySemanticsLabel('Search, Shortcut Ctrl+K'), findsOneWidget);
    });
  });

  group('LoadingSkeleton', () {
    testWidgets('renders rows (static)', (tester) async {
      await tester.pumpWidget(
        wrap(const LoadingSkeleton(rows: 4, animate: false)),
      );
      // 4 rows x (leading + title + subtitle).
      expect(find.byType(SkeletonBox), findsNWidgets(12));
      expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    });

    testWidgets('pulses when animated and stops on dispose', (tester) async {
      await tester.pumpWidget(
        wrap(const LoadingSkeleton(rows: 2, leading: false, subtitle: false)),
      );
      FadeTransition fade() => tester.widget<FadeTransition>(
        find.descendant(
          of: find.byType(LoadingSkeleton),
          matching: find.byType(FadeTransition),
        ),
      );
      final first = fade().opacity.value;
      await tester.pump(const Duration(milliseconds: 450));
      expect(fade().opacity.value, isNot(first));
      expect(find.byType(SkeletonBox), findsNWidgets(2));
      await tester.pumpWidget(wrap(const SizedBox()));
    });
  });
}
