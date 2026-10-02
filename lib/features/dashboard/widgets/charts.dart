import 'package:flutter/material.dart';

import '../../../core/widgets/design_system.dart';

/// Row of day cells for the last [length] local days ending [today]
/// (filled = studied that day). [days] and [today] are `localDay` values.
class ActivityStrip extends StatelessWidget {
  const ActivityStrip({
    super.key,
    required this.days,
    required this.today,
    this.length = 7,
  });

  final Set<DateTime> days;
  final DateTime today;
  final int length;

  static const _weekdayInitials = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  List<DateTime> get _window => [
    for (var i = length - 1; i >= 0; i--)
      DateTime.utc(today.year, today.month, today.day - i),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final window = _window;
    final active = [for (final d in window) days.contains(d)];
    final activeCount = active.where((a) => a).length;
    final compact = length > 14;
    return Semantics(
      label: 'Studied on $activeCount of the last $length days',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: compact ? 14 : 22,
              child: CustomPaint(
                painter: _StripPainter(
                  active: active,
                  fill: theme.colorScheme.primary,
                  empty: colors.skeleton,
                  todayRing: colors.border,
                  gap: compact ? 2 : 4,
                ),
              ),
            ),
            if (!compact) ...[
              Gaps.h4,
              Row(
                children: [
                  for (final d in window)
                    Expanded(
                      child: Text(
                        _weekdayInitials[d.weekday - 1],
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: d == today
                              ? theme.colorScheme.onSurface
                              : colors.faintText,
                          fontWeight: d == today ? FontWeight.w600 : null,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StripPainter extends CustomPainter {
  _StripPainter({
    required this.active,
    required this.fill,
    required this.empty,
    required this.todayRing,
    required this.gap,
  });

  final List<bool> active;
  final Color fill;
  final Color empty;
  final Color todayRing;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final n = active.length;
    if (n == 0 || size.width <= 0) return;
    final cell = (size.width - gap * (n - 1)) / n;
    final radius = Radius.circular(size.height < 18 ? 2.5 : 4);
    for (var i = 0; i < n; i++) {
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(i * (cell + gap), 0, cell, size.height),
        radius,
      );
      canvas.drawRRect(rect, Paint()..color = active[i] ? fill : empty);
      if (i == n - 1 && !active[i]) {
        canvas.drawRRect(
          rect.deflate(0.5),
          Paint()
            ..color = todayRing
            ..style = PaintingStyle.stroke,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_StripPainter old) =>
      old.fill != fill ||
      old.empty != empty ||
      old.todayRing != todayRing ||
      old.gap != gap ||
      !_listEquals(old.active, active);

  static bool _listEquals(List<bool> a, List<bool> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Thin horizontal bar showing [ratio] (0..1) in the accent color.
class AccuracyBar extends StatelessWidget {
  const AccuracyBar({super.key, required this.ratio, this.height = 6});

  final double ratio;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _BarPainter(
          ratio: ratio.clamp(0, 1).toDouble(),
          fill: Theme.of(context).colorScheme.primary,
          track: AppColors.of(context).skeleton,
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({required this.ratio, required this.fill, required this.track});

  final double ratio;
  final Color fill;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, radius),
      Paint()..color = track,
    );
    if (ratio <= 0) return;
    final width = (size.width * ratio).clamp(size.height, size.width);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, width.toDouble(), size.height),
        radius,
      ),
      Paint()..color = fill,
    );
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.ratio != ratio || old.fill != fill || old.track != track;
}

/// "82%" for a 0..1 ratio, "–" for null.
String formatPercent(double? ratio) =>
    ratio == null ? '–' : '${(ratio * 100).round()}%';
