import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/data_providers.dart';
import '../../data/repositories/organization_repository.dart';
import '../theme/app_colors.dart';
import 'error_message.dart';

/// Pin / unpin toggle (outlined pin = not pinned, filled = pinned).
///
/// - `PinButton(pinned:, onChanged:)`: any action.
/// - `PinButton.item(kind:, id:, pinned:)`: a note / quiz / deck via
///   `OrganizationRepository.setPinned`.
/// - `PinButton.subject(subjectId:, pinned:)`: a subject.
///
/// Disabled while saving; errors are shown as a snackbar. Only owners can
/// pin (the repository rejects shared items), so hide it for those.
class PinButton extends ConsumerStatefulWidget {
  const PinButton({
    super.key,
    required this.pinned,
    required Future<void> Function(bool pinned) this.onChanged,
    this.size = 20,
  }) : kind = null,
       id = null,
       _subject = false;

  const PinButton.item({
    super.key,
    required TaggableKind this.kind,
    required String this.id,
    required this.pinned,
    this.size = 20,
  }) : _subject = false,
       onChanged = null;

  const PinButton.subject({
    super.key,
    required String subjectId,
    required this.pinned,
    this.size = 20,
  }) : kind = null,
       id = subjectId,
       _subject = true,
       onChanged = null;

  final bool pinned;
  final Future<void> Function(bool pinned)? onChanged;
  final double size;

  /// Item kind ([PinButton.item]).
  final TaggableKind? kind;

  /// Item / subject id (null for the custom constructor).
  final String? id;
  final bool _subject;

  @override
  ConsumerState<PinButton> createState() => _PinButtonState();
}

class _PinButtonState extends ConsumerState<PinButton> {
  bool _busy = false;

  Future<void> _toggle() async {
    final next = !widget.pinned;
    setState(() => _busy = true);
    try {
      if (widget.onChanged case final change?) {
        await change(next);
      } else {
        final org = ref.read(organizationRepositoryProvider);
        if (widget._subject) {
          await org.setSubjectPinned(widget.id!, next);
        } else {
          await org.setPinned(widget.kind!, widget.id!, next);
        }
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pinned = widget.pinned;
    return IconButton(
      key: const Key('pin-button'),
      tooltip: pinned ? 'Unpin' : 'Pin',
      isSelected: pinned,
      icon: Icon(
        Icons.push_pin_outlined,
        size: widget.size,
        color: AppColors.of(context).mutedText,
      ),
      selectedIcon: Icon(
        Icons.push_pin,
        size: widget.size,
        color: Theme.of(context).colorScheme.primary,
      ),
      onPressed: _busy ? null : _toggle,
    );
  }
}
