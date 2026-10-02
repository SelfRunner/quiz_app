import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/core/theme/app_theme.dart';

/// A screen exercising most themed components.
class _Kitchen extends StatelessWidget {
  const _Kitchen();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Title'),
      actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.search))],
    ),
    body: ListView(
      padding: Insets.page,
      children: [
        Text('Display', style: Theme.of(context).textTheme.displaySmall),
        Gaps.h8,
        FilledButton(onPressed: () {}, child: const Text('Filled')),
        FilledButton.tonal(onPressed: () {}, child: const Text('Tonal')),
        OutlinedButton(onPressed: () {}, child: const Text('Outlined')),
        TextButton(onPressed: () {}, child: const Text('Text')),
        ElevatedButton(onPressed: () {}, child: const Text('Elevated')),
        const TextField(decoration: InputDecoration(labelText: 'Label')),
        const Chip(label: Text('Chip')),
        FilterChip(label: const Text('Filter'), onSelected: (_) {}),
        const Card(
          child: ListTile(title: Text('Tile'), subtitle: Text('Sub')),
        ),
        const Divider(),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('A')),
            ButtonSegment(value: 1, label: Text('B')),
          ],
          selected: const {0},
          onSelectionChanged: (_) {},
        ),
        Checkbox(value: true, onChanged: (_) {}),
        const LinearProgressIndicator(value: 0.5),
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const AlertDialog(
                title: Text('Dialog'),
                content: Text('Body'),
              ),
            ),
            child: const Text('Open dialog'),
          ),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton(
      onPressed: () {},
      child: const Icon(Icons.add),
    ),
    bottomNavigationBar: NavigationBar(
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
        NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
      ],
    ),
  );
}

void main() {
  for (final (name, build, brightness) in [
    ('light', AppTheme.light, Brightness.light),
    ('dark', AppTheme.dark, Brightness.dark),
  ]) {
    group('$name theme', () {
      final theme = build();

      test('is M3, neutral and flat', () {
        expect(theme.useMaterial3, isTrue);
        expect(theme.brightness, brightness);
        expect(theme.colorScheme.brightness, brightness);
        expect(theme.extension<AppColors>(), isNotNull);
        expect(theme.appBarTheme.elevation, 0);
        expect(theme.appBarTheme.scrolledUnderElevation, 0);
        expect(theme.appBarTheme.surfaceTintColor, Colors.transparent);
        expect(theme.cardTheme.elevation, 0);
        final shape = theme.cardTheme.shape! as RoundedRectangleBorder;
        expect(shape.side.width, 1);
        expect(shape.borderRadius, Radii.lgAll);
        expect(theme.textTheme.bodyMedium!.fontSize, 14);
        expect(theme.textTheme.bodyLarge!.height, greaterThan(1.4));
        expect(theme.textTheme.bodyMedium!.color, theme.colorScheme.onSurface);
        // Neutral surfaces: low saturation.
        final hsl = HSLColor.fromColor(theme.colorScheme.surface);
        expect(hsl.saturation, lessThan(0.2));
      });

      testWidgets('renders the component kitchen sink', (tester) async {
        tester.view.physicalSize = const Size(800, 2000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(theme: theme, home: const _Kitchen()),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Filled'), findsOneWidget);

        await tester.tap(find.text('Open dialog'));
        await tester.pumpAndSettle();
        expect(find.text('Dialog'), findsOneWidget);
      });
    });
  }

  test('AppColors lerp and copyWith', () {
    final mid = AppColors.light.lerp(AppColors.dark, 0.5);
    expect(mid.card, isNot(AppColors.light.card));
    expect(AppColors.light.copyWith(card: Colors.red).card, Colors.red);
    expect(AppColors.light.lerp(null, 0.5), same(AppColors.light));
  });

  testWidgets('AppColors.of falls back by brightness without the extension', (
    tester,
  ) async {
    late AppColors colors;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Builder(
          builder: (context) {
            colors = AppColors.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(colors, same(AppColors.dark));
  });

  test('ThemeModeController keeps the mode in memory without Hive', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(themeModeProvider), ThemeMode.system);
    container.read(themeModeProvider.notifier).set(ThemeMode.dark);
    expect(container.read(themeModeProvider), ThemeMode.dark);
  });
}
