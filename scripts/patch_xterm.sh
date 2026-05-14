#!/bin/bash
# Patches xterm 4.0.0 bugs in the pub cache.
# Run after every `flutter pub get`.
#
# Patch 1: Enter key broken with secure IME on Android
#   - terminal_view.dart: performAction triggers Enter for any TextInputAction
#   - custom_text_edit.dart: autocorrect/enableSuggestions/enableIMEPersonalizedLearning all true
# Patch 2: RangeError crash in eraseLineToCursor (end == 0 -> getWidth(-1))
# Patch 3: RangeError in eraseLineFromCursor/eraseChars (_cursorX can be -1)
# Patch 4: Terminal view doesn't auto-scroll on new SSH output (_stickToBottom not reset)
# Patch 5: scrollBack negative bug - cursor on wrong line after terminal maximize
# Patch 6: Underline/verticalBar cursor Y offset missing offset.dy
# Patch 7: IME text duplication with predictive IMEs (delta tracking, no key filter)
# Patch 8: Selection painted ON TOP of text (swapped render order)

set -e

# Find xterm package - first try .dart_tool/package_config.json (reliable on CI),
# then fall back to searching the pub cache directly.
XTERM_DIR=""
if [ -f .dart_tool/package_config.json ]; then
  XTERM_DIR=$(grep -A2 '"name": "xterm"' .dart_tool/package_config.json \
    | grep '"rootUri"' \
    | sed 's/.*"rootUri": "file:\/\/\(.*\)"/\1/' \
    | head -1)/lib/src
fi

if [ -z "$XTERM_DIR" ] || [ ! -d "$XTERM_DIR" ]; then
  XTERM_DIR=$(find ~/.pub-cache/hosted -path '*/xterm-4.0.0/lib/src' -type d 2>/dev/null | head -1)
fi

if [ -z "$XTERM_DIR" ] || [ ! -d "$XTERM_DIR" ]; then
  echo "xterm 4.0.0 not found in pub cache, skipping patches"
  exit 0
fi

echo "Patching xterm at: $XTERM_DIR"
# Verify we found the right package
if [ ! -f "$XTERM_DIR/terminal_view.dart" ]; then
  echo "ERROR: $XTERM_DIR does not contain xterm source files"
  exit 1
fi

echo "Patching xterm at: $XTERM_DIR"

# Patch 1a: terminal_view.dart - Enter key for any TextInputAction
FILE="$XTERM_DIR/terminal_view.dart"
if grep -q "action == TextInputAction.done" "$FILE" 2>/dev/null; then
  sed -i 's/action == TextInputAction\.done/true/' "$FILE"
  echo "  [1/4] Patched terminal_view.dart (Enter key)"
elif grep -q "onAction: (action) {" "$FILE" 2>/dev/null; then
  echo "  [1/4] terminal_view.dart already patched"
else
  echo "  [1/4] terminal_view.dart pattern not found, skipping"
fi

# Patch 1b: custom_text_edit.dart - disable secure IME triggers
FILE="$XTERM_DIR/ui/custom_text_edit.dart"
if [ -f "$FILE" ]; then
  sed -i 's/autocorrect: false/autocorrect: true/' "$FILE"
  sed -i 's/enableSuggestions: false/enableSuggestions: true/' "$FILE"
  sed -i 's/enableIMEPersonalizedLearning: false/enableIMEPersonalizedLearning: true/' "$FILE"
  echo "  [1/4] Patched custom_text_edit.dart (IME settings)"
fi

# Patch 2: line.dart - eraseRange end==0 guard
FILE="$XTERM_DIR/core/buffer/line.dart"
if [ -f "$FILE" ]; then
  if grep -q 'end < _length && getWidth(end - 1)' "$FILE" && ! grep -q 'end > 0 && end < _length' "$FILE"; then
    sed -i 's/end < _length && getWidth(end - 1)/end \> 0 \&\& end < _length \&\& getWidth(end - 1)/' "$FILE"
    echo "  [2/4] Patched line.dart (eraseRange guard)"
  else
    echo "  [2/4] line.dart already patched or pattern not found"
  fi
fi

# Patch 3: buffer.dart - use cursorX getter instead of _cursorX in erase methods
FILE="$XTERM_DIR/core/buffer/buffer.dart"
if [ -f "$FILE" ]; then
  # eraseLineFromCursor: currentLine.eraseRange(_cursorX, ...) -> eraseRange(cursorX, ...)
  sed -i '/eraseLineFromCursor/,/^  }/ s/eraseRange(_cursorX,/eraseRange(cursorX,/' "$FILE"
  # eraseChars: final start = _cursorX -> final start = cursorX
  sed -i '/eraseChars/,/^  }/ s/final start = _cursorX/final start = cursorX/' "$FILE"
  echo "  [3/4] Patched buffer.dart (cursorX getter)"
fi

# Patch 4: render.dart - reset _stickToBottom on terminal change
FILE="$XTERM_DIR/ui/render.dart"
if [ -f "$FILE" ]; then
  if grep -q 'void _onTerminalChange' "$FILE" && ! grep -A2 '_onTerminalChange' "$FILE" | grep -q '_stickToBottom = true'; then
    sed -i '/void _onTerminalChange()/a\    _stickToBottom = true;' "$FILE"
    echo "  [4/4] Patched render.dart (_stickToBottom)"
  else
    echo "  [4/4] render.dart already patched or pattern not found"
  fi
fi

# Patch 5: buffer.dart - scrollBack negative bug (cursor on wrong line after maximize)
FILE="$XTERM_DIR/core/buffer/buffer.dart"
if [ -f "$FILE" ]; then
  if grep -q 'scrollBack => height - viewHeight' "$FILE" && ! grep -q 'scrollBack => max(0' "$FILE"; then
    sed -i 's/int get scrollBack => height - viewHeight/int get scrollBack => max(0, height - viewHeight)/' "$FILE"
    echo "  [5/6] Patched buffer.dart (scrollBack clamp)"
  else
    echo "  [5/6] buffer.dart scrollBack already patched or pattern not found"
  fi
fi

# Patch 6: painter.dart - underline and verticalBar cursor Y offset missing offset.dy
FILE="$XTERM_DIR/ui/painter.dart"
if [ -f "$FILE" ]; then
  if grep -q 'Offset(offset.dx, _cellSize.height - 1)' "$FILE"; then
    sed -i 's/Offset(offset.dx, _cellSize.height - 1)/Offset(offset.dx, offset.dy + _cellSize.height - 1)/' "$FILE"
    sed -i 's/Offset(offset.dx + _cellSize.width, _cellSize.height - 1)/Offset(offset.dx + _cellSize.width, offset.dy + _cellSize.height - 1)/' "$FILE"
    sed -i 's/Offset(offset.dx, 0),$/Offset(offset.dx, offset.dy),/' "$FILE"
    sed -i 's/Offset(offset.dx, _cellSize.height),$/Offset(offset.dx, offset.dy + _cellSize.height),/' "$FILE"
    echo "  [6/6] Patched painter.dart (cursor Y offset)"
  else
    echo "  [6/6] painter.dart already patched or pattern not found"
  fi
fi

# Patch 7: custom_text_edit.dart - prevent IME text duplication (e.g. Baidu
#   predictive text: "app" + "apple" prediction -> was "appapple")
#   Root cause: updateEditingValue reset editing state to _initEditingState
#   after each character, breaking the IME's text accumulation. When the IME
#   later commits a predicted word, the delta was computed from the stale
#   initial prefix instead of from the last committed text.
#   Fixed: track _lastCommittedText and compute delta from it, removing the
#   reset that corrupted the IME's text buffer.
FILE="$XTERM_DIR/ui/custom_text_edit.dart"
if [ -f "$FILE" ]; then
  # Patch 7a: add _lastCommittedText field after _currentEditingState
  if grep -q "_lastCommittedText" "$FILE"; then
    echo "  [7/8] custom_text_edit.dart already patched (IME delta tracking)"
  else
    # Add field (safe initializer, _initEditingState is set at connection time)
    perl -i -pe 's/(late var _currentEditingState = _initEditingState\.copyWith\(\);)/$1\n\n  String _lastCommittedText = _initEditingState.text;/' "$FILE"
    # Fix: change initializer from _initEditingState.text to empty string
    # (widget not available during field init, _lastCommittedText is set in _openInputConnection)
    perl -i -pe "s/String _lastCommittedText = _initEditingState.text;/String _lastCommittedText = '';/" "$FILE"
    # Initialize in _openInputConnection
    perl -i -pe 's/(_connection!\.setEditingState\(_initEditingState\);)/$1\n      _lastCommittedText = _initEditingState.text;/' "$FILE"
    echo "  [7/8] Added _lastCommittedText field"
  fi

  # Patch 7b: rewrite updateEditingValue to use _lastCommittedText delta
  if grep -q "text.startsWith(_lastCommittedText)" "$FILE"; then
    echo "  [8/8] custom_text_edit.dart already patched (updateEditingValue)"
  else
    # Replace the delta computation + reset block
    perl -i -pe 'BEGIN{undef $/;} s/if \(_currentEditingState\.text\.length < _initEditingState\.text\.length\) \{\n      widget\.onDelete\(\);\n    \} else \{\n      final text = _currentEditingState\.text;\n      final initText = _initEditingState\.text;\n      final textDelta = text\.startsWith\(initText\)\n          \? text\.substring\(initText\.length\)\n          : text;\n\n      widget\.onInsert\(textDelta\);\n    \}\n\n    \/\/ Reset editing state if composing is done\n    if \(_currentEditingState\.composing\.isCollapsed \&\&\n        _currentEditingState\.text != _initEditingState\.text\) \{\n      _connection!\.setEditingState\(_initEditingState\);\n    \}/final text = _currentEditingState.text;\n\n    if (text.length < _lastCommittedText.length) {\n      widget.onDelete();\n      _lastCommittedText = text;\n    } else {\n      final textDelta = text.startsWith(_lastCommittedText)\n          ? text.substring(_lastCommittedText.length)\n          : text;\n      widget.onInsert(textDelta);\n      _lastCommittedText = text;\n    }/gsm' "$FILE"
    echo "  [8/8] Patched updateEditingValue (delta tracking)"
  fi
fi

# Patch 8: render.dart - paint selection BEFORE text lines so text is readable
#   Original order: paintLine (bg+fg) -> cursor -> selection -> highlights
#   The selection rectangle was painted ON TOP of rendered text, completely
#   obscuring it with a solid gray block.
#   Fixed: paint selection BEFORE paintLine, then text renders on top. For
#   cells with default background the selection highlight shows through; for
#   cells with explicit background the cell bg paints over it - both cases
#   leave the text character clearly visible on top.
FILE="$XTERM_DIR/ui/render.dart"
if [ -f "$FILE" ]; then
  if grep -q "Paint selection highlight first" "$FILE"; then
    echo "  [9/9] render.dart already patched (selection render order)"
  else
    # Add selection painting before the line loop, remove the one after
    perl -i -pe 'BEGIN{undef $/;} s/(final effectLastLine = lastLine\.clamp\(0, lines\.length - 1\);)/$1\n\n    if (_controller.selection != null) {\n      _paintSelection(\n        canvas,\n        _controller.selection!,\n        effectFirstLine,\n        effectLastLine,\n      );\n    }/g' "$FILE"
    # Remove the duplicate selection paint after the loop
    perl -i -pe 'BEGIN{undef $/;} s/\n    if \(_controller\.selection != null\) \{\n      _paintSelection\(\n        canvas,\n        _controller\.selection!,\n        effectFirstLine,\n        effectLastLine,\n      \);\n    \}//g' "$FILE"
    echo "  [9/9] Patched render.dart (selection render order)"
  fi
fi

# Patch 9: custom_text_edit.dart - handle keyEvent.character for desktop keyboard
#   With hardwareKeyboardOnly:false, CustomTextEdit uses _handleKeyEvent which
#   returns KeyEventResult.ignored for regular character keys (no text input on
#   desktop). CustomKeyboardListener has a keyEvent.character fallback; add the
#   same fallback here so desktop keyboard input works while keeping IME support.
FILE="$XTERM_DIR/ui/custom_text_edit.dart"
if [ -f "$FILE" ]; then
  if grep -q "event.character" "$FILE" 2>/dev/null; then
    echo "  [10/10] custom_text_edit.dart already patched (keyEvent.character fallback)"
  else
    perl -i -0 -pe 's/return widget\.onKeyEvent\(focusNode, event\);/final result = widget.onKeyEvent(focusNode, event);\n      if (result == KeyEventResult.ignored) {\n        if (event.character != null \&\& event.character != "") {\n          widget.onInsert(event.character!);\n          return KeyEventResult.handled;\n        }\n      }\n      return result;/gms' "$FILE"
    echo "  [10/10] Patched custom_text_edit.dart (keyEvent.character fallback)"
  fi
fi

echo "Done. All xterm patches applied."

# Final verification - confirm key patches took effect
if grep -q "action == TextInputAction.done" "$XTERM_DIR/terminal_view.dart" 2>/dev/null; then
  echo "ERROR: terminal_view.dart was NOT patched (Enter key fix missing)"
  exit 1
fi
echo "Verification passed - all patches confirmed."
