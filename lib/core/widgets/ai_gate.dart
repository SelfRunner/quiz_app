import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../ai/ai_providers.dart';
import '../router/routes.dart';
import 'locked_feature.dart';

/// Wraps an AI entry point (button, menu item, card). While no AI provider
/// key/model is configured the child is shown dimmed with a lock badge and a
/// tap opens [showAiSetupSheet] instead of [onReady].
///
/// The [child] should not handle taps itself (pass `onPressed: null`-free
/// visuals or wrap a plain widget); [onReady] runs when AI is configured.
class AiGate extends ConsumerWidget {
  const AiGate({super.key, required this.child, required this.onReady});

  final Widget child;
  final VoidCallback onReady;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readiness = ref.watch(aiReadinessProvider).value;
    final ready = readiness?.isConfigured ?? false;
    if (ready) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onReady,
        child: child,
      );
    }
    return LockedFeature(
      tooltip: 'Set up AI in Settings to use this',
      onTap: () => showAiSetupSheet(context, reason: readiness?.reason),
      child: child,
    );
  }
}

/// True when AI is configured; for code paths that gate imperatively.
bool isAiReady(WidgetRef ref) =>
    ref.read(aiReadinessProvider).value?.isConfigured ?? false;

/// Explains that AI needs the user's own API key and links to Settings.
Future<void> showAiSetupSheet(BuildContext context, {String? reason}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Set up AI',
                style: Theme.of(sheetContext).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              reason ??
                  'AI features use your own API key (Gemini, OpenAI, Anthropic '
                      'or an OpenAI-compatible endpoint). Keys stay on this '
                      'device and are never uploaded.',
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  context.push(AppRoutes.settings);
                },
                child: const Text('Open Settings'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
