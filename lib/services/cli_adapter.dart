abstract class CliAdapter {
  String get id;
  String get name;
  String get startCommand;
  bool get supportsImages;

  /// Format user input for the CLI tool
  String formatInput(String text, {List<String>? imagePaths});

  /// Parse raw output from the CLI, extracting meaningful content
  /// Returns null if output should be filtered out
  String? parseOutput(String rawOutput);

  /// Get the start command with optional working directory
  String getStartCommand({String? workingDir}) {
    return startCommand;
  }
}
