import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/data_providers.dart';
import '../sharing_ui.dart';

/// Owner id -> display label for everything shared with the current user.
///
/// Best effort: resolves to an empty map when offline or on any error (no
/// automatic retries), and is kept alive after a successful load so detail
/// screens don't refetch. `SharedWithMeScreen` invalidates it on refresh.
final sharedOwnerNamesProvider =
    FutureProvider.autoDispose<Map<String, String>>((ref) async {
      try {
        final shares = await ref.watch(shareRepositoryProvider).sharedWithMe();
        ref.keepAlive();
        return {
          for (final s in shares)
            if (s.owner != null) s.ownerId: profileLabel(s.owner),
        };
      } catch (_) {
        return const {};
      }
    }, retry: (_, _) => null);

/// Small "Shared by `name`" chip for read-only (not owned) subjects, notes and
/// quizzes. Pass [ownerName] when known; otherwise the name is looked up from
/// the shared-with-me list (falls back to "Shared with you").
///
/// Widget tests that render it without [ownerName] should override
/// `shareRepositoryProvider`.
class SharedByChip extends ConsumerWidget {
  const SharedByChip({super.key, required this.ownerId, this.ownerName});

  /// `ownerId` of the shared entity.
  final String ownerId;

  /// Owner display name, if the caller already has it.
  final String? ownerName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name =
        ownerName ?? ref.watch(sharedOwnerNamesProvider).value?[ownerId];
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: "View only. Copy it to your account if you'd like to edit it.",
      child: Chip(
        avatar: Icon(
          Icons.people_alt_outlined,
          size: 18,
          color: scheme.onTertiaryContainer,
        ),
        label: Text(
          name == null ? 'Shared with you' : 'Shared by $name',
          overflow: TextOverflow.ellipsis,
        ),
        labelStyle: TextStyle(color: scheme.onTertiaryContainer),
        backgroundColor: scheme.tertiaryContainer,
        side: BorderSide.none,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
