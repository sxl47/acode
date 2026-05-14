# Patches xterm 4.0.0 bugs in the pub cache.
# Run after every flutter pub get on Windows.

$ErrorActionPreference = 'Stop'

# Find xterm package - first try .dart_tool/package_config.json (reliable on CI),
# then fall back to searching the pub cache directly.
$srcDir = $null
$pkgConfig = ".dart_tool\package_config.json"
if (Test-Path $pkgConfig) {
  $config = Get-Content $pkgConfig -Raw | ConvertFrom-Json
  $xtermPkg = $config.packages | Where-Object { $_.name -eq 'xterm' }
  if ($xtermPkg) {
    $uri = $xtermPkg.rootUri
    if ($uri -match '^file:///') {
      $srcDir = [IO.Path]::Combine(($uri -replace '^file:///', ''), 'lib', 'src')
    } elseif ($uri -match '^file://') {
      $srcDir = [IO.Path]::Combine(($uri -replace '^file://', ''), 'lib', 'src')
    }
  }
}

if (-not $srcDir -or -not (Test-Path $srcDir)) {
  $pubCache = if ($env:LOCALAPPDATA) { "$env:LOCALAPPDATA\Pub\Cache" } else { "$env:USERPROFILE\.pub-cache" }
  $xtermDirs = Get-ChildItem -Path "$pubCache\hosted" -Recurse -Filter "xterm-4.0.0" -Directory -ErrorAction SilentlyContinue
  if ($xtermDirs) {
    $srcDir = [IO.Path]::Combine($xtermDirs[0].FullName, 'lib', 'src')
  }
}

if (-not $srcDir -or -not (Test-Path $srcDir)) {
  Write-Host "xterm 4.0.0 not found in pub cache, skipping patches"
  exit 0
}

Write-Host "Patching xterm at: $srcDir"
# Verify we found the right package
if (-not (Test-Path "$srcDir\terminal_view.dart")) {
  Write-Host "ERROR: $srcDir does not contain xterm source files"
  exit 1
}

function Patch-File {
  param($Path, $Pattern, $Replacement, $Description)
  if (-not (Test-Path $Path)) { Write-Host "  $Description - file not found, skipping"; return }
  $content = Get-Content $Path -Raw
  if ($content -match $Pattern) {
    $content = $content -replace $Pattern, $Replacement
    Set-Content $Path $content -NoNewline
    Write-Host "  $Description - patched"
  } else {
    Write-Host "  $Description - already patched or pattern not found"
  }
}

# Patch 1a: terminal_view.dart - Enter key for any TextInputAction
Patch-File `
  -Path "$srcDir\terminal_view.dart" `
  -Pattern "action == TextInputAction\.done" `
  -Replacement "true" `
  -Description "[1/4] Patched terminal_view.dart (Enter key)"

# Patch 1b: custom_text_edit.dart - disable secure IME triggers
$imeFile = "$srcDir\ui\custom_text_edit.dart"
if (Test-Path $imeFile) {
  $content = Get-Content $imeFile -Raw
  $changed = $false
  if ($content -match 'autocorrect: false') { $content = $content -replace 'autocorrect: false', 'autocorrect: true'; $changed = $true }
  if ($content -match 'enableSuggestions: false') { $content = $content -replace 'enableSuggestions: false', 'enableSuggestions: true'; $changed = $true }
  if ($content -match 'enableIMEPersonalizedLearning: false') { $content = $content -replace 'enableIMEPersonalizedLearning: false', 'enableIMEPersonalizedLearning: true'; $changed = $true }
  if ($changed) { Set-Content $imeFile $content -NoNewline }
  Write-Host "  [1/4] Patched custom_text_edit.dart (IME settings)"
}

# Patch 2: line.dart - eraseRange end==0 guard
$lineFile = "$srcDir\core\buffer\line.dart"
if (Test-Path $lineFile) {
  $content = Get-Content $lineFile -Raw
  if ($content -match 'end < _length && getWidth\(end - 1\)' -and $content -notmatch 'end > 0 && end < _length') {
    $content = $content -replace 'end < _length && getWidth\(end - 1\)', 'end > 0 && end < _length && getWidth(end - 1)'
    Set-Content $lineFile $content -NoNewline
    Write-Host "  [2/4] Patched line.dart (eraseRange guard)"
  } else {
    Write-Host "  [2/4] line.dart already patched or pattern not found"
  }
}

# Patch 3: buffer.dart - use cursorX getter instead of _cursorX
$bufFile = "$srcDir\core\buffer\buffer.dart"
if (Test-Path $bufFile) {
  $content = Get-Content $bufFile -Raw
  $changed = $false
  if ($content -match 'eraseLineFromCursor') {
    $newContent = $content -replace '(eraseRange\()_cursorX', '${1}cursorX'
    if ($newContent -ne $content) { $content = $newContent; $changed = $true }
  }
  if ($content -match 'eraseChars') {
    $newContent = $content -replace '(final start = )_cursorX', '${1}cursorX'
    if ($newContent -ne $content) { $content = $newContent; $changed = $true }
  }
  if ($changed) { Set-Content $bufFile $content -NoNewline }
  Write-Host "  [3/4] Patched buffer.dart (cursorX getter)"
}

# Patch 4: render.dart - reset _stickToBottom on terminal change
$renderFile = "$srcDir\ui\render.dart"
if (Test-Path $renderFile) {
  $content = Get-Content $renderFile -Raw
  if ($content -match 'void _onTerminalChange\(\)' -and $content -notmatch '_stickToBottom = true') {
    $content = $content -replace 'void _onTerminalChange\(\) \{', "void _onTerminalChange() {`n    _stickToBottom = true;"
    Set-Content $renderFile $content -NoNewline
    Write-Host "  [4/4] Patched render.dart (_stickToBottom)"
  } else {
    Write-Host "  [4/4] render.dart already patched or pattern not found"
  }
}

# Patch 5: buffer.dart - scrollBack negative bug
$bufFile2 = "$srcDir\core\buffer\buffer.dart"
if (Test-Path $bufFile2) {
  $content = Get-Content $bufFile2 -Raw
  if ($content -match 'int get scrollBack => height - viewHeight' -and $content -notmatch 'max\(0') {
    $content = $content -replace 'int get scrollBack => height - viewHeight', 'int get scrollBack => max(0, height - viewHeight)'
    Set-Content $bufFile2 $content -NoNewline
    Write-Host "  [5/6] Patched buffer.dart (scrollBack clamp)"
  } else {
    Write-Host "  [5/6] buffer.dart scrollBack already patched or pattern not found"
  }
}

# Patch 6: painter.dart - underline/verticalBar cursor Y offset
$paintFile = "$srcDir\ui\painter.dart"
if (Test-Path $paintFile) {
  $content = Get-Content $paintFile -Raw
  if ($content -match 'Offset\(offset\.dx, _cellSize\.height - 1\)') {
    $content = $content -replace 'Offset\(offset\.dx, _cellSize\.height - 1\)', 'Offset(offset.dx, offset.dy + _cellSize.height - 1)'
    $content = $content -replace 'Offset\(offset\.dx \+ _cellSize\.width, _cellSize\.height - 1\)', 'Offset(offset.dx + _cellSize.width, offset.dy + _cellSize.height - 1)'
    $content = $content -replace 'Offset\(offset\.dx, 0\),(?=[^)]*\))', 'Offset(offset.dx, offset.dy),'
    $content = $content -replace 'Offset\(offset\.dx, _cellSize\.height\),(?=[^)]*\))', 'Offset(offset.dx, offset.dy + _cellSize.height),'
    Set-Content $paintFile $content -NoNewline
    Write-Host "  [6/6] Patched painter.dart (cursor Y offset)"
  } else {
    Write-Host "  [6/6] painter.dart already patched or pattern not found"
  }
}

# Patch 7: custom_text_edit.dart - IME text duplication (Baidu predictive text)
$customFile = "$srcDir\ui\custom_text_edit.dart"
if (Test-Path $customFile) {
  $content = Get-Content $customFile -Raw

  # Patch 7a: add _lastCommittedText field
  if ($content -notmatch "_lastCommittedText") {
    $content = $content -replace '(late var _currentEditingState = _initEditingState\.copyWith\(\);)', "`$1`n`n  String _lastCommittedText = '';"
    $content = $content -replace '(_connection!\.setEditingState\(_initEditingState\);)', "`$1`n      _lastCommittedText = _initEditingState.text;"
    Set-Content $customFile $content -NoNewline
    Write-Host "  [7/8] Added _lastCommittedText field"
  } else {
    Write-Host "  [7/8] custom_text_edit.dart already patched (IME delta tracking)"
  }

  # Patch 7b: rewrite updateEditingValue
  if ($content -notmatch "_lastCommittedText\.length") {
    $pattern = 'if \(_currentEditingState\.text\.length < _initEditingState\.text\.length\) \{\s*widget\.onDelete\(\);\s*\} else \{\s*final text = _currentEditingState\.text;\s*final initText = _initEditingState\.text;\s*final textDelta = text\.startsWith\(initText\)\s*\?\s*text\.substring\(initText\.length\)\s*:\s*text;\s*widget\.onInsert\(textDelta\);\s*\}\s*// Reset editing state if composing is done\s*if \(_currentEditingState\.composing\.isCollapsed &&\s*_currentEditingState\.text != _initEditingState\.text\) \{\s*_connection!\.setEditingState\(_initEditingState\);\s*\}'
    $replacement = 'final text = _currentEditingState.text;`n`n    if (text.length < _lastCommittedText.length) {`n      widget.onDelete();`n      _lastCommittedText = text;`n    } else {`n      final textDelta = text.startsWith(_lastCommittedText)`n          ? text.substring(_lastCommittedText.length)`n          : text;`n      widget.onInsert(textDelta);`n      _lastCommittedText = text;`n    }'
    $newContent = $content -replace $pattern, $replacement
    if ($newContent -ne $content) {
      $content = $newContent
      Set-Content $customFile $content -NoNewline
      Write-Host "  [8/8] Patched updateEditingValue (delta tracking)"
    } else {
      Write-Host "  [8/8] custom_text_edit.dart already patched or pattern not found"
    }
  } else {
    Write-Host "  [8/8] custom_text_edit.dart already patched (updateEditingValue)"
  }
}

# Patch 8: render.dart - selection painted ON TOP of text
$renderFile2 = "$srcDir\ui\render.dart"
if (Test-Path $renderFile2) {
  $content = Get-Content $renderFile2 -Raw
  if ($content -match "Paint selection highlight first") {
    Write-Host "  [9/9] render.dart already patched (selection render order)"
  } else {
    # Add selection paint before line loop
    $insertPattern = '(final effectLastLine = lastLine\.clamp\(0, lines\.length - 1\);)'
    $insertText = "`$1`n`n    if (_controller.selection != null) {`n      _paintSelection(`n        canvas,`n        _controller.selection!,`n        effectFirstLine,`n        effectLastLine,`n      );`n    }"
    $content = $content -replace $insertPattern, $insertText

    # Remove selection paint after the loop
    $removePattern = '`n    if \(_controller\.selection != null\) \{`n      _paintSelection\(`n        canvas,`n        _controller\.selection!,`n        effectFirstLine,`n        effectLastLine,`n      \);`n    \}'
    $content = $content -replace $removePattern, ''

    Set-Content $renderFile2 $content -NoNewline
    Write-Host "  [9/9] Patched render.dart (selection render order)"
  }
}

Write-Host "Done. All xterm patches applied."

# Final verification - confirm key patches took effect
$termFile = "$srcDir\terminal_view.dart"
if (Test-Path $termFile) {
  $content = Get-Content $termFile -Raw
  if ($content -match "action == TextInputAction\.done") {
    Write-Host "ERROR: terminal_view.dart was NOT patched (Enter key fix missing)"
    exit 1
  }
}
Write-Host "Verification passed - all patches confirmed."
