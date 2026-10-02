import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'responsive.dart';

/// Shows [builder]'s content sized to fit: a centred dialog capped at
/// [maxWidth] × 80% of the screen height on medium+ widths, and a bottom
/// sheet that only grows as tall as its content (capped at 85%) on phones.
///
/// [builder] must return content that shrink-wraps vertically (a `Column`
/// with `mainAxisSize: MainAxisSize.min`, or a scroll view with
/// `shrinkWrap: true`). Long content should scroll inside its own
/// `Flexible` region.
///
/// Use this for pickers, confirmations with details, info panels and short
/// forms. Real editors use [showAdaptiveEditor].
Future<T?> showAdaptivePanel<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  String? title,
  List<Widget> actions = const [],
  double maxWidth = 560,
  bool isDismissible = true,
}) {
  final size = MediaQuery.sizeOf(context);
  Widget body(BuildContext ctx) => _PanelBody(
    title: title,
    actions: actions,
    child: Builder(builder: builder),
  );

  if (Breakpoints.isMedium(context)) {
    return showDialog<T>(
      context: context,
      barrierDismissible: isDismissible,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(Insets.lg),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxWidth,
            maxHeight: size.height * 0.8,
          ),
          child: body(ctx),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    isDismissible: isDismissible,
    constraints: BoxConstraints(maxHeight: size.height * 0.85),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: body(ctx),
    ),
  );
}

/// Shows a real editor: full screen on phones, a dialog capped at
/// [maxWidth] × [maxHeightFactor] of the screen on medium+ widths. The editor
/// owns its own scaffold/app bar and scrolling.
Future<T?> showAdaptiveEditor<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double maxWidth = 720,
  double maxHeightFactor = 0.85,
}) {
  if (!Breakpoints.isMedium(context)) {
    return Navigator.of(context).push<T>(
      MaterialPageRoute(fullscreenDialog: true, builder: builder),
    );
  }
  final size = MediaQuery.sizeOf(context);
  return showDialog<T>(
    context: context,
    builder: (ctx) => Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.all(Insets.lg),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: size.height * maxHeightFactor,
        ),
        child: Builder(builder: builder),
      ),
    ),
  );
}

class _PanelBody extends StatelessWidget {
  const _PanelBody({required this.child, this.title, this.actions = const []});

  final Widget child;
  final String? title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Insets.lg,
              Insets.lg,
              Insets.lg,
              Insets.sm,
            ),
            child: Text(title!, style: theme.textTheme.titleLarge),
          ),
        Flexible(child: child),
        if (actions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Insets.lg,
              Insets.sm,
              Insets.lg,
              Insets.lg,
            ),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: Insets.sm,
              runSpacing: Insets.sm,
              children: actions,
            ),
          ),
      ],
    );
  }
}
