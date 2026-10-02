import 'package:flutter/material.dart';

import '../../../../core/widgets/design_system.dart';

/// Preset subject colors (ARGB32, stored in `Subject.color`). Used only as
/// small accents (dots), never as fills.
const List<int> subjectPalette = [
  0xFF3F51B5, // indigo
  0xFF1E88E5, // blue
  0xFF00897B, // teal
  0xFF43A047, // green
  0xFFC0CA33, // lime
  0xFFFFB300, // amber
  0xFFF4511E, // deep orange
  0xFFE53935, // red
  0xFFD81B60, // pink
  0xFF8E24AA, // purple
  0xFF6D4C41, // brown
  0xFF546E7A, // blue grey
];

/// Row of selectable color dots (with a "no color" option).
class SubjectColorPicker extends StatelessWidget {
  const SubjectColorPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final int? selected;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    Widget dot({required int? value, required String tooltip}) {
      final isSelected = selected == value;
      return Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          selected: isSelected,
          label: tooltip,
          child: InkResponse(
            key: Key('subject-color-${value ?? 'none'}'),
            onTap: () => onChanged(value),
            radius: 18,
            child: AnimatedContainer(
              duration: Motion.fast,
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? onSurface : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: value == null
                  ? Icon(Icons.block, size: 16, color: colors.faintText)
                  : SubjectColorDot(color: value, size: 18),
            ),
          ),
        ),
      );
    }

    return Wrap(
      spacing: Insets.xs,
      runSpacing: Insets.xs,
      children: [
        dot(value: null, tooltip: 'No color'),
        for (final c in subjectPalette) dot(value: c, tooltip: 'Color'),
      ],
    );
  }
}
