import 'package:flutter/material.dart';

import '../../../core/widgets/design_system.dart';

/// Shows [builder] as a dialog on wide screens and as a tall bottom sheet on
/// phones. The panel pops with its result.
Future<T?> showPickerPanel<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  if (Breakpoints.isMedium(context)) {
    return showDialog<T>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 680),
          child: builder(context),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) =>
        FractionallySizedBox(heightFactor: 0.88, child: builder(context)),
  );
}

/// Title row + scrollable body + action bar, shared by the pickers.
class PickerScaffold extends StatelessWidget {
  const PickerScaffold({
    super.key,
    required this.title,
    required this.body,
    required this.actions,
    this.header,
  });

  final String title;

  /// Fixed content under the title (search field, upload button, ...).
  final Widget? header;
  final Widget body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.xl,
            Insets.lg,
            Insets.xl,
            Insets.sm,
          ),
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (header != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Insets.xl,
              0,
              Insets.xl,
              Insets.sm,
            ),
            child: header,
          ),
        Expanded(child: body),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.hairline)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Insets.xl,
              Insets.md,
              Insets.xl,
              Insets.md,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (final (i, a) in actions.indexed) ...[
                  if (i > 0) Gaps.w8,
                  a,
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Small neutral pill ("Shared", "Uploading…").
class TagPill extends StatelessWidget {
  const TagPill({super.key, required this.label, this.icon, this.color});

  final String label;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final fg = color ?? colors.mutedText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Insets.sm, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: Radii.smAll,
        border: Border.all(color: colors.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: fg), Gaps.w4],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg),
          ),
        ],
      ),
    );
  }
}
