enum MessageRole {
  user,
  assistant,
  system,
}

class ChatMessage {
  final String id;
  final String sessionId;
  final MessageRole role;
  String content;
  final DateTime timestamp;
  List<String>? imagePaths;
  bool isStreaming;

  ChatMessage({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.imagePaths,
    this.isStreaming = false,
  }) : timestamp = timestamp ?? DateTime.now();

  ChatMessage copyWith({
    String? content,
    List<String>? imagePaths,
    bool? isStreaming,
  }) {
    return ChatMessage(
      id: id,
      sessionId: sessionId,
      role: role,
      content: content ?? this.content,
      timestamp: timestamp,
      imagePaths: imagePaths ?? this.imagePaths,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }
}
