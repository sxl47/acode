import 'ssh_service.dart';

/// Escapes a string for safe use inside single-quoted shell strings.
/// Replaces each ' with '\'' (end quote, escaped quote, start quote).
String _shellEscape(String s) => s.replaceAll("'", r"'\''");

class TmuxSessionInfo {
  final String name;
  final String? attached;
  final String? windows;

  TmuxSessionInfo({
    required this.name,
    this.attached,
    this.windows,
  });

  static TmuxSessionInfo? parse(String line) {
    // Format: name: windows (attached)
    final match = RegExp(r'^([^:]+):\s+(\d+)\s+windows\s*(\(attached\))?$').firstMatch(line.trim());
    if (match == null) return null;
    return TmuxSessionInfo(
      name: match.group(1)!,
      windows: match.group(2),
      attached: match.group(3),
    );
  }
}

class TmuxService {
  final SshService _ssh;

  TmuxService(this._ssh);

  Future<List<TmuxSessionInfo>> listSessions() async {
    try {
      final result = await _ssh.exec('tmux list-sessions 2>/dev/null || true');
      if (result.trim().isEmpty) return [];
      return result
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .map((line) => TmuxSessionInfo.parse(line))
          .where((info) => info != null)
          .cast<TmuxSessionInfo>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> createSession(String name, String command, {String? workingDir}) async {
    final dir = (workingDir != null && workingDir.isNotEmpty) ? workingDir : '~';
    final escapedName = _shellEscape(name);
    final escapedCmd = _shellEscape(command);
    // Don't single-quote paths starting with ~ so bash can expand them
    final cdDir = (dir == '~' || dir.startsWith('~/'))
        ? dir
        : "'${_shellEscape(dir)}'";
    await _ssh.exec(
      "bash -c \"cd $cdDir && tmux new-session -d -s '$escapedName' '$escapedCmd'\"",
    );
  }

  Future<void> sendKeys(String sessionName, String input) async {
    // Inside single quotes, only ' and \ need escaping
    final escaped = input
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"'\''");
    final escapedName = _shellEscape(sessionName);
    await _ssh.exec("tmux send-keys -t '$escapedName' '$escaped' Enter");
  }

  Future<void> sendRawKeys(String sessionName, String input) async {
    // Send without Enter key - for special key combos
    final escaped = input
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"'\''");
    final escapedName = _shellEscape(sessionName);
    await _ssh.exec("tmux send-keys -t '$escapedName' '$escaped'");
  }

  Future<String> captureOutput(String sessionName) async {
    final escapedName = _shellEscape(sessionName);
    return await _ssh.exec("tmux capture-pane -t '$escapedName' -p -S -500");
  }

  Future<bool> sessionExists(String name) async {
    final escapedName = _shellEscape(name);
    final result = await _ssh.exec("tmux has-session -t '$escapedName' 2>&1; echo \$?");
    // Check for exact exit code 0 (not just absence of '1', which would
    // false-match exit codes like 127)
    return result.trimRight().endsWith('0');
  }

  Future<void> killSession(String name) async {
    final escapedName = _shellEscape(name);
    await _ssh.exec("tmux kill-session -t '$escapedName'");
  }

  Future<void> killAllSessions() async {
    await _ssh.exec('tmux kill-server 2>/dev/null || true');
  }
}
