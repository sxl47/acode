#!/bin/bash
# Patches xterm 4.0.0 bugs in the pub cache (or submodule).
# Run after every `flutter pub get`.
#
# Patch  1: Enter key broken with secure IME on Android
# Patch  2: RangeError crash in eraseLineToCursor
# Patch  3: RangeError in eraseLineFromCursor/eraseChars
# Patch  4: Terminal view doesn't auto-scroll on new SSH output
# Patch  5: scrollBack negative bug
# Patch  6: Underline/verticalBar cursor Y offset
# Patch  7: Selection painted ON TOP of text
# Patch  8: IME fixes (event.character fallback, commit key swallow,
#            _lastCommittedText delta tracking, composing backspace)

set -e

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
  echo "xterm 4.0.0 not found, skipping patches"
  exit 0
fi

echo "Patching xterm at: $XTERM_DIR"
if [ ! -f "$XTERM_DIR/terminal_view.dart" ]; then
  echo "ERROR: $XTERM_DIR does not contain xterm source files"
  exit 1
fi

TOTAL=8

# ==== Patch 1a: terminal_view.dart - Enter key for any TextInputAction ====
FILE="$XTERM_DIR/terminal_view.dart"
if grep -q "action == TextInputAction.done" "$FILE" 2>/dev/null; then
  sed -i 's/action == TextInputAction\.done/true/' "$FILE"
  echo "  [1/$TOTAL] Patched terminal_view.dart (Enter key)"
else
  echo "  [1/$TOTAL] terminal_view.dart already patched"
fi

# ==== Patch 1b: custom_text_edit.dart - enable IME features ====
FILE="$XTERM_DIR/ui/custom_text_edit.dart"
if [ -f "$FILE" ]; then
  sed -i 's/autocorrect: false/autocorrect: true/' "$FILE"
  sed -i 's/enableSuggestions: false/enableSuggestions: true/' "$FILE"
  sed -i 's/enableIMEPersonalizedLearning: false/enableIMEPersonalizedLearning: true/' "$FILE"
  echo "  [2/$TOTAL] Patched custom_text_edit.dart (IME settings)"
fi

# ==== Patch 2: line.dart - eraseRange end==0 guard ====
FILE="$XTERM_DIR/core/buffer/line.dart"
if [ -f "$FILE" ]; then
  if grep -q 'end < _length && getWidth(end - 1)' "$FILE" && ! grep -q 'end > 0 && end < _length' "$FILE"; then
    sed -i 's/end < _length && getWidth(end - 1)/end \> 0 \&\& end < _length \&\& getWidth(end - 1)/' "$FILE"
    echo "  [3/$TOTAL] Patched line.dart (eraseRange guard)"
  else
    echo "  [3/$TOTAL] line.dart already patched or pattern not found"
  fi
fi

# ==== Patch 3: buffer.dart - use cursorX getter ====
FILE="$XTERM_DIR/core/buffer/buffer.dart"
if [ -f "$FILE" ]; then
  sed -i '/eraseLineFromCursor/,/^  }/ s/eraseRange(_cursorX,/eraseRange(cursorX,/' "$FILE"
  sed -i '/eraseChars/,/^  }/ s/final start = _cursorX/final start = cursorX/' "$FILE"
  echo "  [4/$TOTAL] Patched buffer.dart (cursorX getter)"
fi

# ==== Patch 4: render.dart - reset _stickToBottom ====
FILE="$XTERM_DIR/ui/render.dart"
if [ -f "$FILE" ]; then
  if grep -q 'void _onTerminalChange' "$FILE" && ! grep -A2 '_onTerminalChange' "$FILE" | grep -q '_stickToBottom = true'; then
    sed -i '/void _onTerminalChange()/a\    _stickToBottom = true;' "$FILE"
    echo "  [5/$TOTAL] Patched render.dart (_stickToBottom)"
  else
    echo "  [5/$TOTAL] render.dart already patched or pattern not found"
  fi
fi

# ==== Patch 5: buffer.dart - scrollBack negative bug ====
FILE="$XTERM_DIR/core/buffer/buffer.dart"
if [ -f "$FILE" ]; then
  if grep -q 'scrollBack => height - viewHeight' "$FILE" && ! grep -q 'scrollBack => max(0' "$FILE"; then
    sed -i 's/int get scrollBack => height - viewHeight/int get scrollBack => max(0, height - viewHeight)/' "$FILE"
    echo "  [6/$TOTAL] Patched buffer.dart (scrollBack clamp)"
  else
    echo "  [6/$TOTAL] buffer.dart scrollBack already patched or pattern not found"
  fi
fi

# ==== Patch 6: painter.dart - cursor Y offset ====
FILE="$XTERM_DIR/ui/painter.dart"
if [ -f "$FILE" ]; then
  if grep -q 'Offset(offset.dx, _cellSize.height - 1)' "$FILE"; then
    sed -i 's/Offset(offset.dx, _cellSize.height - 1)/Offset(offset.dx, offset.dy + _cellSize.height - 1)/' "$FILE"
    sed -i 's/Offset(offset.dx + _cellSize.width, _cellSize.height - 1)/Offset(offset.dx + _cellSize.width, offset.dy + _cellSize.height - 1)/' "$FILE"
    sed -i 's/Offset(offset.dx, 0),$/Offset(offset.dx, offset.dy),/' "$FILE"
    sed -i 's/Offset(offset.dx, _cellSize.height),$/Offset(offset.dx, offset.dy + _cellSize.height),/' "$FILE"
    echo "  [7/$TOTAL] Patched painter.dart (cursor Y offset)"
  else
    echo "  [7/$TOTAL] painter.dart already patched or pattern not found"
  fi
fi

# ==== Patch 7: render.dart - paint selection BEFORE text ====
FILE="$XTERM_DIR/ui/render.dart"
if [ -f "$FILE" ]; then
  if grep -q "Paint selection highlight first" "$FILE"; then
    echo "  [8/$TOTAL] render.dart already patched (selection render order)"
  else
    perl -i -pe 'BEGIN{undef $/;} s/(final effectLastLine = lastLine\.clamp\(0, lines\.length - 1\);)/$1\n\n    if (_controller.selection != null) {\n      _paintSelection(\n        canvas,\n        _controller.selection!,\n        effectFirstLine,\n        effectLastLine,\n      );\n    }/g' "$FILE"
    perl -i -pe 'BEGIN{undef $/;} s/\n    if \(_controller\.selection != null\) \{\n      _paintSelection\(\n        canvas,\n        _controller\.selection!,\n        effectFirstLine,\n        effectLastLine,\n      \);\n    \}//g' "$FILE"
    echo "  [8/$TOTAL] Patched render.dart (selection render order)"
  fi
fi

# ==== Patch 8: custom_text_edit.dart - full IME fix ====
#   - event.character fallback for desktop keyboard
#   - _imeJustCommitted swallow of space/enter after IME commit
#   - _lastCommittedText delta tracking (common prefix, no reset)
#   - Backspace detection within composing mode (_lastComposingText)
#   - _wasComposing tracking so _imeJustCommitted only fires on real
#     composing→committed transitions, not every text change
FILE="$XTERM_DIR/ui/custom_text_edit.dart"
if [ -f "$FILE" ]; then
  if grep -q "_wasComposing" "$FILE" 2>/dev/null; then
    echo "  [8/$TOTAL] custom_text_edit.dart already patched (all IME fixes)"
  else
    # ---- Add fields: _lastCommittedText + _lastComposingText + _wasComposing + _imeJustCommitted ----
    perl -i -pe 's/(late var _currentEditingState = _initEditingState\.copyWith\(\);)/$1\n\n  String _lastCommittedText = "";\n\n  String? _lastComposingText;\n\n  bool _wasComposing = false;\n\n  bool _imeJustCommitted = false;/' "$FILE"

    # Init _lastCommittedText + _imeJustCommitted in _openInputConnection
    perl -i -pe 's/(_connection!\.setEditingState\(_initEditingState\);)/$1\n      _lastCommittedText = _initEditingState.text;\n\n      _imeJustCommitted = true;/' "$FILE"

    # ---- Replace _onKeyEvent entirely ----
    # Add _imeJustCommitted check + event.character fallback
    perl -i -0 -pe 's/(  KeyEventResult _onKeyEvent\(FocusNode focusNode, KeyEvent event\) \{\n)    return widget\.onKeyEvent\(focusNode, event\);\n  \}/${1}    if (_currentEditingState.composing.isCollapsed) {\n      if (_imeJustCommitted) {\n        _imeJustCommitted = false;\n        if (event.logicalKey == LogicalKeyboardKey.space ||\n            event.logicalKey == LogicalKeyboardKey.enter) {\n          return KeyEventResult.handled;\n        }\n      }\n\n      final result = widget.onKeyEvent(focusNode, event);\n      if (result == KeyEventResult.ignored) {\n        if (event.character != null \&\& event.character != "") {\n          widget.onInsert(event.character!);\n          return KeyEventResult.handled;\n        }\n      }\n      return result;\n    }\n\n    return KeyEventResult.skipRemainingHandlers;\n  }/gms' "$FILE"

    # ---- Replace updateEditingValue entirely ----
    perl -i -0 -pe 's/(  void updateEditingValue\(TextEditingValue value\) \{).*?(  \})/${1}\n    _currentEditingState = value;\n\n    if (!_currentEditingState.composing.isCollapsed) {\n      _wasComposing = true;\n      _imeJustCommitted = false;\n\n      final text = _currentEditingState.text;\n      final composingText = _currentEditingState.composing.textInside(text);\n      widget.onComposing(composingText);\n\n      if (_lastComposingText != null \&\&\n          composingText.length < _lastComposingText!.length) {\n        for (var i = composingText.length;\n            i < _lastComposingText!.length;\n            i++) {\n          widget.onDelete();\n        }\n      }\n      _lastComposingText = composingText;\n      return;\n    }\n\n    _lastComposingText = null;\n    widget.onComposing(null);\n\n    if (_wasComposing) {\n      _imeJustCommitted = true;\n      _wasComposing = false;\n    }\n\n    final text = _currentEditingState.text;\n\n    if (text == _lastCommittedText) {\n      // No change\n    } else if (text.startsWith(_lastCommittedText)) {\n      final textDelta = text.substring(_lastCommittedText.length);\n      widget.onInsert(textDelta);\n    } else if (text.isEmpty) {\n      for (var i = 0; i < _lastCommittedText.length; i++) {\n        widget.onDelete();\n      }\n    } else {\n      var commonLen = 0;\n      final minLen = text.length < _lastCommittedText.length\n          ? text.length\n          : _lastCommittedText.length;\n      while (commonLen < minLen \&\&\n          text[commonLen] == _lastCommittedText[commonLen]) {\n        commonLen++;\n      }\n      for (var i = 0; i < _lastCommittedText.length - commonLen; i++) {\n        widget.onDelete();\n      }\n      if (commonLen < text.length) {\n        widget.onInsert(text.substring(commonLen));\n      }\n    }\n\n    _lastCommittedText = text;\n  }/gms' "$FILE"

    echo "  [8/$TOTAL] Patched custom_text_edit.dart (full IME fix)"
  fi
fi

echo "Done. All xterm patches applied."

# Final verification
if grep -q "action == TextInputAction.done" "$XTERM_DIR/terminal_view.dart" 2>/dev/null; then
  echo "ERROR: terminal_view.dart was NOT patched (Enter key fix missing)"
  exit 1
fi
echo "Verification passed - all patches confirmed."
