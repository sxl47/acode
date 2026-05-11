enum SessionStatus {
  connecting,
  active,
  disconnected,
  error,
}

class Session {
  final String id;
  String serverId;
  String cliToolId;
  String? cliToolCommand;
  String tmuxSessionName;
  String title;
  SessionStatus status;
  DateTime createdAt;
  DateTime lastActiveAt;
  String? workingDir;

  Session({
    required this.id,
    required this.serverId,
    required this.cliToolId,
    this.cliToolCommand,
    required this.tmuxSessionName,
    required this.title,
    this.status = SessionStatus.connecting,
    DateTime? createdAt,
    DateTime? lastActiveAt,
    this.workingDir,
  })  : createdAt = createdAt ?? DateTime.now(),
        lastActiveAt = lastActiveAt ?? DateTime.now();

  void touch() {
    lastActiveAt = DateTime.now();
  }
}
