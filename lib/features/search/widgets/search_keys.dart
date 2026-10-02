import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// ↑ / ↓ handling for a search field that drives a result list of [count]
/// items (wraps around; Home / End jump). Enter is left to the field's
/// `onSubmitted` so it is never handled twice.
KeyEventResult handleSearchNavKey(
  KeyEvent event, {
  required int count,
  required int selected,
  required ValueChanged<int> onSelect,
}) {
  if (event is KeyUpEvent || count == 0) return KeyEventResult.ignored;
  final key = event.logicalKey;
  if (key == LogicalKeyboardKey.arrowDown) {
    onSelect(selected < 0 ? 0 : (selected + 1) % count);
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.arrowUp) {
    onSelect(selected <= 0 ? count - 1 : selected - 1);
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.pageDown && event is KeyDownEvent) {
    onSelect((selected + 5).clamp(0, count - 1));
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.pageUp && event is KeyDownEvent) {
    onSelect((selected - 5).clamp(0, count - 1));
    return KeyEventResult.handled;
  }
  return KeyEventResult.ignored;
}

/// Whether [event] is Ctrl+Enter / Cmd+Enter.
bool isModifiedEnter(KeyEvent event) {
  if (event is! KeyDownEvent) return false;
  final key = event.logicalKey;
  if (key != LogicalKeyboardKey.enter &&
      key != LogicalKeyboardKey.numpadEnter) {
    return false;
  }
  final kb = HardwareKeyboard.instance;
  return kb.isControlPressed || kb.isMetaPressed;
}
