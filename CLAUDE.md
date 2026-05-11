# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ACode is a Flutter app that manages remote CLI coding sessions over SSH. It connects to servers, creates tmux sessions running tools like Claude Code, Aider, OpenCode, or plain shell, and renders the remote terminal locally via an xterm widget.

## Commands

```bash
flutter pub get          # Install dependencies
flutter run              # Run in debug mode
flutter test             # Run all tests
flutter test test/some_test.dart  # Run a single test
flutter analyze          # Static analysis (uses flutter_lints)
flutter build apk        # Android build
flutter build ios        # iOS build
flutter build linux      # Linux desktop build
flutter build web        # Web build
```

## Architecture

Four-layer structure under `lib/`:

- **models/** — Data classes: `ServerConfig`, `CliTool`, `Session`, `ChatMessage`. Hand-written Hive `TypeAdapter`s in `adapters.dart` for local persistence.
- **services/** — Business logic layer:
  - `SshService` wraps `dartssh2` (password + key auth, manual DNS resolution for Android IPv6 issues)
  - `TmuxService` manages tmux sessions over SSH (list, create, kill, send keys, capture pane)
  - `TerminalService` binds an xterm `Terminal` to an SSH shell, handles tmux attach and auto-reconnect
  - `SessionManager` orchestrates session lifecycle and discovers existing `acode_*` tmux sessions
  - `SftpService` uploads files to `~/acode-uploads/` with 7-day cleanup
  - `adapters/claude_adapter.dart` formats input for `claude` CLI (supports `--image`), `adapters/generic_adapter.dart` is the fallback
- **providers/** — Riverpod state management:
  - `SettingsProvider` (AsyncNotifier) — persists servers and CLI tools in Hive boxes
  - `SshProvider` — per-server SSH connection lifecycle
  - `SessionProvider` — per-server session list, active session, chat messages
- **screens/** — UI: `HomeScreen` (server list), `ConnectScreen` (add/edit server), `SessionScreen` (full-screen terminal), `SettingsScreen` (manage CLI tools)

## Data Flow

Server config → Home screen auto-connects → discovers remote `acode_*` tmux sessions → user picks CLI tool → `SessionManager` creates tmux session → `SessionScreen` opens SSH shell → `tmux attach` → xterm renders output in real-time.

## Key Dependencies

- `dartssh2` — SSH client
- `flutter_riverpod` — state management
- `hive_flutter` / `hive` — local NoSQL persistence
- `xterm` — terminal emulator widget
- `image_picker` — send images to CLI tools
- `google_fonts` — custom fonts

## Conventions

- Lint rules: `package:flutter_lints/flutter.yaml` (default, no overrides)
- Theme: Material 3, dark theme, purple seed color (#7C3AED), scaffold background #0F0F1A
- Hive box names: `servers`, `cli_tools`, `sessions`, `chat_messages`
- Tmux sessions managed by the app are prefixed with `acode_`
- SDK constraint: `^3.13.0-27.0.dev` (Dart dev channel)
