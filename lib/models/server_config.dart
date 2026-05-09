class ServerConfig {
  final String id;
  String name;
  String host;
  int port;
  String username;
  String? password;
  String? privateKeyPath;
  String? privateKeyContent;
  String? passphrase;
  String defaultWorkingDir;

  ServerConfig({
    required this.id,
    required this.name,
    required this.host,
    this.port = 22,
    required this.username,
    this.password,
    this.privateKeyPath,
    this.privateKeyContent,
    this.passphrase,
    this.defaultWorkingDir = '~',
  });

  bool get useKeyAuth => privateKeyContent != null && privateKeyContent!.isNotEmpty;

  ServerConfig copyWith({
    String? name,
    String? host,
    int? port,
    String? username,
    String? password,
    String? privateKeyPath,
    String? privateKeyContent,
    String? passphrase,
    String? defaultWorkingDir,
  }) {
    return ServerConfig(
      id: id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      privateKeyPath: privateKeyPath ?? this.privateKeyPath,
      privateKeyContent: privateKeyContent ?? this.privateKeyContent,
      passphrase: passphrase ?? this.passphrase,
      defaultWorkingDir: defaultWorkingDir ?? this.defaultWorkingDir,
    );
  }
}
