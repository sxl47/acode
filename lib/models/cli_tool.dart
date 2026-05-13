class CliTool {
  final String id;
  String name;
  String command;
  String description;
  String icon;
  bool supportsImages;
  String? imageFlag;

  CliTool({
    required this.id,
    required this.name,
    required this.command,
    this.description = '',
    this.icon = 'terminal',
    this.supportsImages = false,
    this.imageFlag,
  });

  static List<CliTool> defaults() {
    return [
      CliTool(
        id: 'generic',
        name: 'Shell',
        command: '',
        description: 'Plain shell session',
        icon: 'terminal',
      ),
      CliTool(
        id: 'claude',
        name: 'Claude Code',
        command: 'claude',
        description: 'Anthropic Claude CLI coding assistant',
        icon: 'smart_toy',
        supportsImages: true,
      ),
      CliTool(
        id: 'opencode',
        name: 'OpenCode',
        command: 'opencode',
        description: 'Open source AI coding tool',
        icon: 'code',
      ),
      CliTool(
        id: 'aider',
        name: 'Aider',
        command: 'aider',
        description: 'AI pair programming in your terminal',
        icon: 'pair_programming',
      ),
    ];
  }
}
