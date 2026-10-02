import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/tokens.dart';

/// Flat outlined card (hairline border, no shadow). Interactive when [onTap]
/// is set: hover darkens the border, keyboard focus draws a focus ring.
/// [accentColor] draws a thin left border (e.g. a subject color).
class AppCard extends StatefulWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding = Insets.card,
    this.margin = EdgeInsets.zero,
    this.accentColor,
    this.selected = false,
    this.color,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? accentColor;
  final bool selected;

  /// Background; defaults to [AppColors.card].
  final Color? color;

  /// Width of the [accentColor] left border.
  static const double accentWidth = 3;

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final interactive = widget.onTap != null || widget.onLongPress != null;
    final BorderSide side;
    if (_focused) {
      side = BorderSide(color: colors.focusRing, width: 2);
    } else if (widget.selected) {
      side = BorderSide(color: Theme.of(context).colorScheme.onSurface);
    } else if (_hovered && interactive) {
      side = BorderSide(color: colors.border);
    } else {
      side = BorderSide(color: colors.hairline);
    }

    Widget content = Padding(padding: widget.padding, child: widget.child);
    if (widget.accentColor != null) {
      content = Stack(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: AppCard.accentWidth,
            ),
            child: content,
          ),
          PositionedDirectional(
            start: 0,
            top: 0,
            bottom: 0,
            width: AppCard.accentWidth,
            child: ColoredBox(color: widget.accentColor!),
          ),
        ],
      );
    }
    if (interactive) {
      content = InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onHover: (v) => setState(() => _hovered = v),
        onFocusChange: (v) => setState(() => _focused = v),
        child: content,
      );
    }
    return Padding(
      padding: widget.margin,
      child: Material(
        color: widget.color ?? colors.card,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: Radii.lgAll, side: side),
        child: content,
      ),
    );
  }
}

/// Compact list row (Notion-style): leading, title, subtitle, trailing and
/// row [actions]. On mouse/keyboard platforms the actions appear on hover or
/// focus (always visible on touch platforms and when [selected]).
class ListRowTile extends StatefulWidget {
  const ListRowTile({
    super.key,
    required this.title,
    this.leading,
    this.subtitle,
    this.trailing,
    this.actions = const [],
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.dense = false,
    this.revealActionsOnHover = true,
    this.padding = Insets.row,
  });

  final Widget title;
  final Widget? leading;
  final Widget? subtitle;

  /// Always-visible trailing widget (e.g. metadata text).
  final Widget? trailing;

  /// Row actions (usually small `IconButton`s or a `PopupMenuButton`).
  final List<Widget> actions;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool dense;
  final bool revealActionsOnHover;
  final EdgeInsetsGeometry padding;

  @override
  State<ListRowTile> createState() => _ListRowTileState();
}

class _ListRowTileState extends State<ListRowTile> {
  bool _hovered = false;
  bool _focusWithin = false;
  bool _rowFocused = false;

  static bool _isTouchPlatform(TargetPlatform p) =>
      p == TargetPlatform.android ||
      p == TargetPlatform.iOS ||
      p == TargetPlatform.fuchsia;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final showActions =
        !widget.revealActionsOnHover ||
        _isTouchPlatform(theme.platform) ||
        _hovered ||
        _focusWithin ||
        widget.selected;

    final row = Padding(
      padding: widget.padding,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: widget.dense ? 28 : 36),
        child: Row(
          children: [
            if (widget.leading != null) ...[
              IconTheme.merge(
                data: IconThemeData(color: colors.mutedText, size: 20),
                child: widget.leading!,
              ),
              Gaps.w12,
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  DefaultTextStyle.merge(
                    style:
                        (widget.dense
                                ? theme.textTheme.bodyMedium
                                : theme.textTheme.bodyLarge)!
                            .copyWith(
                              fontWeight: FontWeight.w500,
                              height: 1.35,
                            ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    child: widget.title,
                  ),
                  if (widget.subtitle != null)
                    DefaultTextStyle.merge(
                      style: theme.textTheme.bodySmall!.copyWith(
                        color: colors.mutedText,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      child: widget.subtitle!,
                    ),
                ],
              ),
            ),
            if (widget.trailing != null) ...[
              Gaps.w8,
              DefaultTextStyle.merge(
                style: theme.textTheme.labelMedium!.copyWith(
                  color: colors.mutedText,
                ),
                child: widget.trailing!,
              ),
            ],
            if (widget.actions.isNotEmpty) ...[
              Gaps.w4,
              AnimatedOpacity(
                key: const ValueKey('list-row-actions'),
                opacity: showActions ? 1 : 0,
                duration: Motion.fast,
                child: IconTheme.merge(
                  data: IconThemeData(color: colors.mutedText, size: 18),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: widget.actions,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (v) => setState(() => _focusWithin = v),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
          color: widget.selected ? colors.pressed : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: Radii.mdAll,
            side: _rowFocused
                ? BorderSide(color: colors.focusRing, width: 2)
                : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            onFocusChange: (v) => setState(() => _rowFocused = v),
            borderRadius: Radii.mdAll,
            child: row,
          ),
        ),
      ),
    );
  }
}
