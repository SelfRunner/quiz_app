import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/design_system.dart';
import '../../../../core/widgets/error_message.dart';
import '../../../../data/data_providers.dart';
import '../../../../study/study_settings.dart';

/// Flashcard settings: daily new-card limit and desired retention, stored
/// on this device via [studySettingsProvider].
class StudySettingsSection extends ConsumerStatefulWidget {
  const StudySettingsSection({super.key});

  static const double minRetention = 0.80;
  static const double maxRetention = 0.95;

  /// Upper bound offered in the UI for the daily new-card limit.
  static const int maxNewCards = 999;

  @override
  ConsumerState<StudySettingsSection> createState() =>
      _StudySettingsSectionState();
}

class _StudySettingsSectionState extends ConsumerState<StudySettingsSection> {
  late final TextEditingController _newCards;
  double? _dragRetention;

  @override
  void initState() {
    super.initState();
    _newCards = TextEditingController(
      text: '${ref.read(studySettingsProvider).newCardsPerDay}',
    );
  }

  @override
  void dispose() {
    _newCards.dispose();
    super.dispose();
  }

  StudySettingsController get _controller =>
      ref.read(studySettingsProvider.notifier);

  void _setNewCards(int value) {
    final v = value.clamp(0, StudySettingsSection.maxNewCards);
    _controller.setNewCardsPerDay(v);
    final text = '$v';
    if (_newCards.text != text) {
      _newCards.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  void _reset() {
    _controller.set(const StudySettings());
    _dragRetention = null;
    _setNewCards(StudySettings.defaultNewCardsPerDay);
    showAppSnackBar(context, 'Study settings reset');
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(studySettingsProvider);
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: colors.mutedText);
    final retention = (_dragRetention ?? settings.desiredRetention).clamp(
      StudySettingsSection.minRetention,
      StudySettingsSection.maxRetention,
    );
    final percent = '${(retention * 100).round()}%';
    final isDefault = settings == const StudySettings();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('New cards per day', style: theme.textTheme.titleSmall),
                  Gaps.h2,
                  Text(
                    'Unseen flashcards introduced each day, across all decks.',
                    style: muted,
                  ),
                ],
              ),
            ),
            Gaps.w12,
            IconButton(
              key: const Key('study-new-cards-minus'),
              tooltip: 'Fewer',
              icon: const Icon(Icons.remove, size: 18),
              onPressed: settings.newCardsPerDay <= 0
                  ? null
                  : () => _setNewCards(settings.newCardsPerDay - 5),
            ),
            SizedBox(
              width: 64,
              child: TextField(
                key: const Key('study-new-cards'),
                controller: _newCards,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                decoration: const InputDecoration(
                  isDense: true,
                  semanticCounterText: '',
                ),
                onChanged: (text) {
                  final n = int.tryParse(text);
                  if (n != null) _controller.setNewCardsPerDay(n);
                },
                onSubmitted: (_) => _setNewCards(settings.newCardsPerDay),
                onTapOutside: (_) {
                  FocusScope.of(context).unfocus();
                  _setNewCards(ref.read(studySettingsProvider).newCardsPerDay);
                },
              ),
            ),
            IconButton(
              key: const Key('study-new-cards-plus'),
              tooltip: 'More',
              icon: const Icon(Icons.add, size: 18),
              onPressed:
                  settings.newCardsPerDay >= StudySettingsSection.maxNewCards
                  ? null
                  : () => _setNewCards(settings.newCardsPerDay + 5),
            ),
          ],
        ),
        Gaps.h16,
        Divider(height: 1, color: colors.hairline),
        Gaps.h16,
        Row(
          children: [
            Expanded(
              child: Text(
                'Desired retention',
                style: theme.textTheme.titleSmall,
              ),
            ),
            Text(
              percent,
              key: const Key('study-retention-value'),
              style: theme.textTheme.titleSmall,
            ),
          ],
        ),
        Gaps.h2,
        Text(
          'How likely you should be to remember a card when it comes back. '
          'Higher means more frequent reviews.',
          style: muted,
        ),
        Slider(
          key: const Key('study-retention'),
          value: retention,
          min: StudySettingsSection.minRetention,
          max: StudySettingsSection.maxRetention,
          divisions: 15,
          label: percent,
          semanticFormatterCallback: (v) => '${(v * 100).round()}%',
          onChanged: (v) => setState(() => _dragRetention = v),
          onChangeEnd: (v) {
            _controller.setDesiredRetention(double.parse(v.toStringAsFixed(2)));
            setState(() => _dragRetention = null);
          },
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            key: const Key('study-reset'),
            onPressed: isDefault ? null : _reset,
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const Text('Reset to defaults'),
          ),
        ),
      ],
    );
  }
}
