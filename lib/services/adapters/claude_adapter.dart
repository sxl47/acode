import '../cli_adapter.dart';

class ClaudeAdapter extends CliAdapter {
  @override
  String get id => 'claude';

  @override
  String get name => 'Claude Code';

  @override
  String get startCommand => 'claude';

  @override
  bool get supportsImages => true;

  @override
  String formatInput(String text, {List<String>? imagePaths}) {
    if (imagePaths == null || imagePaths.isEmpty) {
      return text;
    }
    // Claude CLI can accept image paths with --image flag
    final paths = imagePaths.join(' ');
    return '--image $paths $text';
  }

  @override
  String? parseOutput(String rawOutput) {
    // Filter out common ANSI escape sequences and control characters
    var output = rawOutput
        .replaceAll(RegExp(r'\x1B\[[0-9;]*[a-zA-Z]'), '')
        .replaceAll(RegExp(r'\x1B\][^\x07]*\x07'), '');

    // Skip empty lines
    if (output.trim().isEmpty) return null;

    return output;
  }
}
