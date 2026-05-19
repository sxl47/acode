#!/bin/bash
# Applies all xterm patches to the forked xterm.dart checkout.
# Usage: bash scripts/apply_patches_to_fork.sh path/to/xterm_fork

set -e

XTERM_DIR="$1"
if [ -z "$XTERM_DIR" ]; then
  echo "Usage: bash scripts/apply_patches_to_fork.sh path/to/xterm_fork"
  exit 1
fi

XTERM_DIR="$XTERM_DIR/lib/src"
if [ ! -f "$XTERM_DIR/terminal_view.dart" ]; then
  echo "ERROR: $XTERM_DIR/terminal_view.dart not found"
  exit 1
fi

# Patch 1a: terminal_view.dart - Enter key for any TextInputAction
FILE="$XTERM_DIR/terminal_view.dart"
if grep -q "action == TextInputAction.done" "$FILE" 2>/dev/null; then
  sed -i 's/action == TextInputAction\.done/true/' "$FILE"
  echo "  [1] Patched terminal_view.dart (Enter key)"
elif grep -q "onAction: (action) {" "$FILE" 2>/dev/null; then
  echo "  [1] terminal_view.dart already patched"
else
  echo "  [1] terminal_view.dart pattern not found, skipping"
fi

# Patch 1b: custom_text_edit.dart - disable secure IME triggers
FILE="$XTERM_DIR/ui/custom_text_edit.dart"
if [ -f "$FILE" ]; then
  sed -i 's/autocorrect: false/autocorrect: true/' "$FILE"
  sed -i 's/enableSuggestions: false/enableSuggestions: true/' "$FILE"
  sed -i 's/enableIMEPersonalizedLearning: false/enableIMEPersonalizedLearning: true/' "$FILE"
  echo "  [2] Patched custom_text_edit.dart (IME settings)"
fi

# Patch 2: line.dart - eraseRange end==0 guard
FILE="$XTERM_DIR/core/buffer/line.dart"
if [ -f "$FILE" ]; then
  if grep -q 'end < _length && getWidth(end - 1)' "$FILE" && ! grep -q 'end > 0 && end < _length' "$FILE"; then
    sed -i 's/end < _length && getWidth(end - 1)/end > 0 \&\& end < _length \&\& getWidth(end - 1)/' "$FILE"
    echo "  [3] Patched line.dart (eraseRange guard)"
  else
    echo "  [3] line.dart already patched or pattern not found"
  fi
fi

# Patch 3: buffer.dart - use cursorX getter in erase methods
FILE="$XTERM_DIR/core/buffer/buffer.dart"
if [ -f "$FILE" ]; then
  sed -i '/eraseLineFromCursor/,/^  }/ s/eraseRange(_cursorX,/eraseRange(cursorX,/' "$FILE"
  sed -i '/eraseChars/,/^  }/ s/final start = _cursorX/final start = cursorX/' "$FILE"
  echo "  [4] Patched buffer.dart (cursorX getter)"
fi

# Patch 4: render.dart - reset _stickToBottom on terminal change
FILE="$XTERM_DIR/ui/render.dart"
if [ -f "$FILE" ]; then
  if grep -q 'void _onTerminalChange' "$FILE" && ! grep -A2 '_onTerminalChange' "$FILE" | grep -q '_stickToBottom = true'; then
    sed -i '/void _onTerminalChange()/a\    _stickToBottom = true;' "$FILE"
    echo "  [5] Patched render.dart (_stickToBottom)"
  else
    echo "  [5] render.dart already patched or pattern not found"
  fi
fi

# Patch 5: buffer.dart - scrollBack negative clamp
FILE="$XTERM_DIR/core/buffer/buffer.dart"
if [ -f "$FILE" ]; then
  if grep -q 'scrollBack => height - viewHeight' "$FILE" && ! grep -q 'max(0' "$FILE"; then
    sed -i 's/int get scrollBack => height - viewHeight/int get scrollBack => max(0, height - viewHeight)/' "$FILE"
    echo "  [6] Patched buffer.dart (scrollBack clamp)"
  else
    echo "  [6] buffer.dart scrollBack already patched or pattern not found"
  fi
fi

# Patch 6: painter.dart - underline/verticalBar cursor Y offset
FILE="$XTERM_DIR/ui/painter.dart"
if [ -f "$FILE" ]; then
  if grep -q 'Offset(offset.dx, _cellSize.height - 1)' "$FILE"; then
    sed -i 's/Offset(offset.dx, _cellSize.height - 1)/Offset(offset.dx, offset.dy + _cellSize.height - 1)/' "$FILE"
    sed -i 's/Offset(offset.dx + _cellSize.width, _cellSize.height - 1)/Offset(offset.dx + _cellSize.width, offset.dy + _cellSize.height - 1)/' "$FILE"
    sed -i 's/Offset(offset.dx, 0),$/Offset(offset.dx, offset.dy),/' "$FILE"
    sed -i 's/Offset(offset.dx, _cellSize.height),$/Offset(offset.dx, offset.dy + _cellSize.height),/' "$FILE"
    echo "  [7] Patched painter.dart (cursor Y offset)"
  else
    echo "  [7] painter.dart already patched or pattern not found"
  fi
fi

# Patch 7: custom_text_edit.dart - IME delta tracking
FILE="$XTERM_DIR/ui/custom_text_edit.dart"
if [ -f "$FILE" ]; then
  # Patch 7a: add _lastCommittedText field
  if grep -q "_lastCommittedText" "$FILE"; then
    echo "  [8] custom_text_edit.dart already patched (IME delta tracking)"
  else
    perl -i -pe 's/(late var _currentEditingState = _initEditingState\.copyWith\(\);)/$1\n\n  String _lastCommittedText = "";/' "$FILE"
    perl -i -pe 's/ String _lastCommittedText = "";/  String _lastCommittedText = "";/' "$FILE"
    perl -i -pe 's/(_connection!\.setEditingState\(_initEditingState\);)/$1\n      _lastCommittedText = _initEditingState.text;/' "$FILE"
    echo "  [8] Added _lastCommittedText field"
  fi

  # Patch 7b: rewrite updateEditingValue delta computation
  if grep -q "text.startsWith(_lastCommittedText)" "$FILE"; then
    echo "  [9] custom_text_edit.dart already patched (updateEditingValue)"
  else
    perl -i -pe 'BEGIN{undef $/;} s/if \(_currentEditingState\.text\.length < _initEditingState\.text\.length\) \{\n      widget\.onDelete\(\);\n    \} else \{\n      final text = _currentEditingState\.text;\n      final initText = _initEditingState\.text;\n      final textDelta = text\.startsWith\(initText\)\n          \? text\.substring\(initText\.length\)\n          : text;\n\n      widget\.onInsert\(textDelta\);\n    \}\n\n    \/\/ Reset editing state if composing is done\n    if \(_currentEditingState\.composing\.isCollapsed \&\&\n        _currentEditingState\.text != _initEditingState\.text\) \{\n      _connection!\.setEditingState\(_initEditingState\);\n    \}/final text = _currentEditingState.text;\n\n    if (text.length < _lastCommittedText.length) {\n      widget.onDelete();\n      _lastCommittedText = text;\n    } else {\n      final textDelta = text.startsWith(_lastCommittedText)\n          ? text.substring(_lastCommittedText.length)\n          : text;\n      widget.onInsert(textDelta);\n      _lastCommittedText = text;\n    }/gsm' "$FILE"
    echo "  [9] Patched updateEditingValue (delta tracking)"
  fi
fi

# Patch 8: render.dart - selection painted ON TOP of text
FILE="$XTERM_DIR/ui/render.dart"
if [ -f "$FILE" ]; then
  if grep -q "Paint selection highlight first" "$FILE"; then
    echo "  [10] render.dart already patched (selection render order)"
  else
    perl -i -pe 'BEGIN{undef $/;} s/(final effectLastLine = lastLine\.clamp\(0, lines\.length - 1\);)/$1\n\n    if (_controller.selection != null) {\n      _paintSelection(\n        canvas,\n        _controller.selection!,\n        effectFirstLine,\n        effectLastLine,\n      );\n    }/g' "$FILE"
    perl -i -pe 'BEGIN{undef $/;} s/\n    if \(_controller\.selection != null\) \{\n      _paintSelection\(\n        canvas,\n        _controller\.selection!,\n        effectFirstLine,\n        effectLastLine,\n      \);\n    \}//g' "$FILE"
    echo "  [10] Patched render.dart (selection render order)"
  fi
fi

# Patch 9: custom_text_edit.dart - keyEvent.character fallback for desktop
FILE="$XTERM_DIR/ui/custom_text_edit.dart"
if [ -f "$FILE" ]; then
  if grep -q "event.character" "$FILE" 2>/dev/null; then
    echo "  [11] custom_text_edit.dart already patched (keyEvent.character fallback)"
  else
    perl -i -0 -pe 's/return widget\.onKeyEvent\(focusNode, event\);/final result = widget.onKeyEvent(focusNode, event);\n      if (result == KeyEventResult.ignored) {\n        if (event.character != null \&\& event.character != "") {\n          widget.onInsert(event.character!);\n          return KeyEventResult.handled;\n        }\n      }\n      return result;/gms' "$FILE"
    echo "  [11] Patched custom_text_edit.dart (keyEvent.character fallback)"
  fi
fi

echo ""
echo "All patches applied. Ready to commit."
