import 'package:flutter/material.dart';

import '../../../../data/models/subject.dart';

/// Preset subject colors (ARGB32, stored in `Subject.color`).
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

/// Display color of a subject (falls back to the theme's primary color).
Color subjectColor(BuildContext context, int? color) =>
    color == null ? Theme.of(context).colorScheme.primary : Color(color);

/// Rounded square with the subject's initial on its color.
class SubjectAvatar extends StatelessWidget {
  const SubjectAvatar({super.key, required this.subject, this.size = 44});

  final Subject subject;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = subjectColor(context, subject.color);
    final onColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black87;
    final title = subject.title.trim();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Text(
        title.isEmpty ? '?' : title.characters.first.toUpperCase(),
        style: TextStyle(
          color: onColor,
          fontWeight: FontWeight.w600,
          fontSize: size * 0.45,
        ),
      ),
    );
  }
}

/// Wrap of selectable color dots (with a "no color" option).
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
    final scheme = Theme.of(context).colorScheme;
    Widget dot({required int? value, required Color color, String? tooltip}) {
      final isSelected = selected == value;
      return Tooltip(
        message: tooltip ?? '',
        child: Semantics(
          button: true,
          selected: isSelected,
          label: tooltip,
          child: InkResponse(
            key: Key('subject-color-${value ?? 'none'}'),
            onTap: () => onChanged(value),
            radius: 22,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? scheme.onSurface : scheme.outlineVariant,
                  width: isSelected ? 3 : 1,
                ),
              ),
              child: isSelected
                  ? Icon(
                      Icons.check,
                      size: 18,
                      color:
                          ThemeData.estimateBrightnessForColor(color) ==
                              Brightness.dark
                          ? Colors.white
                          : Colors.black87,
                    )
                  : null,
            ),
          ),
        ),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        dot(value: null, color: scheme.primary, tooltip: 'Default color'),
        for (final c in subjectPalette)
          dot(value: c, color: Color(c), tooltip: 'Color'),
      ],
    );
  }
}
