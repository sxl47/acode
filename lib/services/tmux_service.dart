import 'ssh_service.dart';

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
    final dir = workingDir ?? '~';
    await _ssh.exec(
      "tmux new-session -d -s '$name' -c '$dir' '$command'",
    );
  }

  Future<void> sendKeys(String sessionName, String input) async {
    // Escape special characters for tmux
    final escaped = input
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"'\''")
        .replaceAll('"', r'\"')
        .replaceAll(r'$', r'\$');
    await _ssh.exec("tmux send-keys -t '$sessionName' '$escaped' Enter");
  }

  Future<void> sendRawKeys(String sessionName, String input) async {
    // Send without Enter key - for special key combos
    final escaped = input
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"'\''");
    await _ssh.exec("tmux send-keys -t '$sessionName' '$escaped'");
  }

  Future<String> captureOutput(String sessionName) async {
    return await _ssh.exec("tmux capture-pane -t '$sessionName' -p -S -500");
  }

  Future<bool> sessionExists(String name) async {
    final result = await _ssh.exec("tmux has-session -t '$name' 2>&1; echo \$?");
    return !result.contains('1');
  }

  Future<void> killSession(String name) async {
    await _ssh.exec("tmux kill-session -t '$name'");
  }

  Future<void> killAllSessions() async {
    await _ssh.exec('tmux kill-server 2>/dev/null || true');
  }
}
