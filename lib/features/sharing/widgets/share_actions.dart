import 'package:flutter/material.dart';

import '../../../data/models/share.dart';

/// Opens the share sheet for a subject, note or quiz the current user owns.
///
/// Cross-feature entry point: subject/note/quiz screens call this; the
/// sharing feature owns the implementation.
Future<void> showShareSheet(
  BuildContext context, {
  required ShareResourceType type,
  required String resourceId,
  required String title,
}) async {
  ScaffoldMessenger.of(context)
      .showSnackBar(const SnackBar(content: Text('Sharing coming soon')));
}

/// Action shown on read-only (shared-with-me) subject/note/quiz screens that
/// copies the resource into the current user's account.
class CopyToAccountButton extends StatelessWidget {
  const CopyToAccountButton({
    super.key,
    required this.type,
    required this.resourceId,
  });

  final ShareResourceType type;
  final String resourceId;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
