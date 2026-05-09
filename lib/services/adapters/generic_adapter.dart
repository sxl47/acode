import '../cli_adapter.dart';

class GenericAdapter extends CliAdapter {
  final String _command;

  GenericAdapter({String command = '', String? toolName})
      : _command = command;

  @override
  String get id => 'generic';

  @override
  String get name => 'Shell';

  @override
  String get startCommand => _command.isEmpty ? 'bash' : _command;

  @override
  bool get supportsImages => false;

  @override
  String formatInput(String text, {List<String>? imagePaths}) {
    return text;
  }

  @override
  String? parseOutput(String rawOutput) {
    var output = rawOutput
        .replaceAll(RegExp(r'\x1B\[[0-9;]*[a-zA-Z]'), '')
        .replaceAll(RegExp(r'\x1B\][^\x07]*\x07'), '');

    if (output.trim().isEmpty) return null;
    return output;
  }
}
