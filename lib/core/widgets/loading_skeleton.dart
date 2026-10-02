import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/tokens.dart';

/// One rounded placeholder block.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 12,
    this.borderRadius = Radii.xsAll,
  });

  final double? width;
  final double height;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: AppColors.of(context).skeleton,
      borderRadius: borderRadius,
    ),
  );
}

/// Placeholder list rows shown while content loads. Gently pulses unless
/// [animate] is false or the platform asks to reduce motion.
///
/// Note: the pulse repeats forever, so tests must use `pump()` rather than
/// `pumpAndSettle()` while it is visible (or pass `animate: false`).
class LoadingSkeleton extends StatefulWidget {
  const LoadingSkeleton({
    super.key,
    this.rows = 3,
    this.leading = true,
    this.subtitle = true,
    this.animate = true,
    this.padding = Insets.row,
  });

  final int rows;
  final bool leading;
  final bool subtitle;
  final bool animate;
  final EdgeInsetsGeometry padding;

  @override
  State<LoadingSkeleton> createState() => _LoadingSkeletonState();
}

class _LoadingSkeletonState extends State<LoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    lowerBound: 0.55,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(LoadingSkeleton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.animate && !reduce) {
      if (!_controller.isAnimating) {
        _controller.repeat(reverse: true).ignore();
      }
    } else {
      _controller
        ..stop()
        ..value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static const _widths = [0.62, 0.78, 0.48, 0.7, 0.55];

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      child: ExcludeSemantics(
        child: FadeTransition(
          opacity: _controller,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < widget.rows; i++)
                Padding(
                  padding: widget.padding,
                  child: Row(
                    children: [
                      if (widget.leading) ...[
                        const SkeletonBox(
                          width: 24,
                          height: 24,
                          borderRadius: Radii.smAll,
                        ),
                        Gaps.w12,
                      ],
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, c) {
                            final w = c.maxWidth;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SkeletonBox(
                                  width: w * _widths[i % _widths.length],
                                  height: 12,
                                ),
                                if (widget.subtitle) ...[
                                  Gaps.h8,
                                  SkeletonBox(width: w * 0.36, height: 9),
                                ],
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
