# ACode

A Flutter app that manages remote CLI coding sessions over SSH. Connect to your servers, create tmux sessions running tools like Claude Code, Aider, OpenCode, or plain shell, and interact with them from your phone or desktop.

## Features

- SSH connection management (password + key auth)
- Tmux session management (create, attach, kill, switch)
- Full terminal emulator with xterm
- Mobile-optimized keyboard bar (Esc, Tab, Ctrl, Alt, arrow keys, etc.)
- Multi-session support with quick switch (Alt+1~9, Alt+Left/Right)
- Auto-discover existing `acode_*` tmux sessions on the server
- Swipe gestures: vertical for PageUp/Down, horizontal for cursor movement
- Copy terminal output to clipboard
- Custom CLI tool support
- Dark/Light theme

## Supported CLI Tools

- Claude Code
- Aider
- OpenCode
- Plain Shell (bash/zsh)
- Custom tools (configurable in Settings)

## Getting Started

### Prerequisites

- Flutter SDK (dev channel `^3.13.0`)
- Android Studio / Xcode (for mobile builds)
- A remote server with SSH access and tmux installed

### Install

```bash
flutter pub get
flutter run
```

### Build

```bash
# Android APK
flutter build apk --release

# Linux desktop
flutter build linux --release

# iOS
flutter build ios --release
```

## Architecture

```
lib/
  models/        # Data classes: ServerConfig, CliTool, Session, ChatMessage
  services/      # Business logic: SSH, Tmux, Terminal, SessionManager, SFTP
  providers/     # Riverpod state management
  screens/       # UI: Home, Connect, Session, Settings
  adapters/      # CLI tool adapters (Claude, generic)
```

### Data Flow

Server config → Home screen auto-connects → discovers remote `acode_*` tmux sessions → user picks CLI tool → SessionManager creates tmux session → SessionScreen opens SSH shell → `tmux attach` → xterm renders output in real-time

## Keyboard Shortcuts (Desktop)

| Shortcut | Action |
|----------|--------|
| Alt+1~9  | Switch to session 1-9 |
| Alt+Left | Previous session |
| Alt+Right| Next session |

## Download

Pre-built APKs are available from [GitHub Actions](../../actions/workflows/build.yml) artifacts.

## License

MIT
