#!/bin/bash
# Patches xterm 4.0.0 bugs in the pub cache.
# Run after every `flutter pub get`.
#
# Patch 1: Enter key broken with secure IME on Android
#   - terminal_view.dart: performAction triggers Enter for any TextInputAction
#   - custom_text_edit.dart: autocorrect/enableSuggestions/enableIMEPersonalizedLearning all true
# Patch 2: RangeError crash in eraseLineToCursor (end == 0 → getWidth(-1))
# Patch 3: RangeError in eraseLineFromCursor/eraseChars (_cursorX can be -1)
# Patch 4: Terminal view doesn't auto-scroll on new SSH output (_stickToBottom not reset)

set -e

# Find xterm package in pub cache
XTERM_DIR=$(find ~/.pub-cache/hosted -path '*/xterm-4.0.0/lib/src' -type d 2>/dev/null | head -1)

if [ -z "$XTERM_DIR" ]; then
  echo "xterm 4.0.0 not found in pub cache, skipping patches"
  exit 0
fi

echo "Patching xterm at: $XTERM_DIR"

# Patch 1a: terminal_view.dart — Enter key for any TextInputAction
FILE="$XTERM_DIR/terminal_view.dart"
if grep -q "action == TextInputAction.done" "$FILE" 2>/dev/null; then
  sed -i 's/action == TextInputAction\.done/true/' "$FILE"
  echo "  [1/4] Patched terminal_view.dart (Enter key)"
elif grep -q "onAction: (action) {" "$FILE" 2>/dev/null; then
  echo "  [1/4] terminal_view.dart already patched"
else
  echo "  [1/4] terminal_view.dart pattern not found, skipping"
fi

# Patch 1b: custom_text_edit.dart — disable secure IME triggers
FILE="$XTERM_DIR/ui/custom_text_edit.dart"
if [ -f "$FILE" ]; then
  sed -i 's/autocorrect: false/autocorrect: true/' "$FILE"
  sed -i 's/enableSuggestions: false/enableSuggestions: true/' "$FILE"
  sed -i 's/enableIMEPersonalizedLearning: false/enableIMEPersonalizedLearning: true/' "$FILE"
  echo "  [1/4] Patched custom_text_edit.dart (IME settings)"
fi

# Patch 2: line.dart — eraseRange end==0 guard
FILE="$XTERM_DIR/core/buffer/line.dart"
if [ -f "$FILE" ]; then
  if grep -q 'end < _length && getWidth(end - 1)' "$FILE" && ! grep -q 'end > 0 && end < _length' "$FILE"; then
    sed -i 's/end < _length && getWidth(end - 1)/end \> 0 \&\& end < _length \&\& getWidth(end - 1)/' "$FILE"
    echo "  [2/4] Patched line.dart (eraseRange guard)"
  else
    echo "  [2/4] line.dart already patched or pattern not found"
  fi
fi

# Patch 3: buffer.dart — use cursorX getter instead of _cursorX in erase methods
FILE="$XTERM_DIR/core/buffer/buffer.dart"
if [ -f "$FILE" ]; then
  # eraseLineFromCursor: currentLine.eraseRange(_cursorX, ...) → eraseRange(cursorX, ...)
  sed -i '/eraseLineFromCursor/,/^  }/ s/eraseRange(_cursorX,/eraseRange(cursorX,/' "$FILE"
  # eraseChars: final start = _cursorX → final start = cursorX
  sed -i '/eraseChars/,/^  }/ s/final start = _cursorX/final start = cursorX/' "$FILE"
  echo "  [3/4] Patched buffer.dart (cursorX getter)"
fi

# Patch 4: render.dart — reset _stickToBottom on terminal change
FILE="$XTERM_DIR/ui/render.dart"
if [ -f "$FILE" ]; then
  if grep -q 'void _onTerminalChange' "$FILE" && ! grep -A2 '_onTerminalChange' "$FILE" | grep -q '_stickToBottom = true'; then
    sed -i '/void _onTerminalChange()/a\    _stickToBottom = true;' "$FILE"
    echo "  [4/4] Patched render.dart (_stickToBottom)"
  else
    echo "  [4/4] render.dart already patched or pattern not found"
  fi
fi

echo "Done. All xterm patches applied."
