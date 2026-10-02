import 'package:flutter/material.dart';

/// Minimal sparkline of attempt scores (0..100), oldest first.
class ScoreTrend extends StatelessWidget {
  const ScoreTrend({super.key, required this.percents});

  final List<int> percents;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Score trend: ${percents.join('%, ')}%',
      child: CustomPaint(
        size: Size.infinite,
        painter: _TrendPainter(
          percents,
          line: scheme.primary,
          fill: scheme.primary.withValues(alpha: 0.12),
          grid: scheme.outlineVariant,
        ),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(
    this.values, {
    required this.line,
    required this.fill,
    required this.grid,
  });

  final List<int> values;
  final Color line;
  final Color fill;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    const pad = 4.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;
    Offset at(int i) => Offset(
      pad + w * i / (values.length - 1),
      pad + h * (1 - values[i].clamp(0, 100) / 100),
    );

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final f in [0.0, 0.5, 1.0]) {
      final y = pad + h * f;
      canvas.drawLine(Offset(pad, y), Offset(pad + w, y), gridPaint);
    }

    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }
    final area = Path.from(path)
      ..lineTo(at(values.length - 1).dx, pad + h)
      ..lineTo(at(0).dx, pad + h)
      ..close();
    canvas
      ..drawPath(area, Paint()..color = fill)
      ..drawPath(
        path,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round,
      );
    final dot = Paint()..color = line;
    for (var i = 0; i < values.length; i++) {
      canvas.drawCircle(at(i), i == values.length - 1 ? 4 : 2.5, dot);
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.values != values || old.line != line || old.fill != fill;
}
