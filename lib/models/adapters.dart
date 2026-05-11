import 'package:hive/hive.dart';
import 'server_config.dart';
import 'cli_tool.dart';
import 'session.dart';
import 'chat_message.dart';

class ServerConfigAdapter extends TypeAdapter<ServerConfig> {
  @override
  final int typeId = 0;

  @override
  ServerConfig read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (int i = 0; i < numOfFields; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return ServerConfig(
      id: fields[0] as String,
      name: fields[1] as String,
      host: fields[2] as String,
      port: fields[3] as int,
      username: fields[4] as String,
      password: fields[5] as String?,
      privateKeyPath: fields[6] as String?,
      privateKeyContent: fields[7] as String?,
      passphrase: fields[8] as String?,
      defaultWorkingDir: fields[9] as String? ?? '~',
    );
  }

  @override
  void write(BinaryWriter writer, ServerConfig obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)..write(obj.id)
      ..writeByte(1)..write(obj.name)
      ..writeByte(2)..write(obj.host)
      ..writeByte(3)..write(obj.port)
      ..writeByte(4)..write(obj.username)
      ..writeByte(5)..write(obj.password)
      ..writeByte(6)..write(obj.privateKeyPath)
      ..writeByte(7)..write(obj.privateKeyContent)
      ..writeByte(8)..write(obj.passphrase)
      ..writeByte(9)..write(obj.defaultWorkingDir);
  }
}

class CliToolAdapter extends TypeAdapter<CliTool> {
  @override
  final int typeId = 1;

  @override
  CliTool read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (int i = 0; i < numOfFields; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return CliTool(
      id: fields[0] as String,
      name: fields[1] as String,
      command: fields[2] as String,
      description: fields[3] as String? ?? '',
      icon: fields[4] as String? ?? 'terminal',
      supportsImages: fields[5] as bool? ?? false,
      imageFlag: fields[6] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, CliTool obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)..write(obj.id)
      ..writeByte(1)..write(obj.name)
      ..writeByte(2)..write(obj.command)
      ..writeByte(3)..write(obj.description)
      ..writeByte(4)..write(obj.icon)
      ..writeByte(5)..write(obj.supportsImages)
      ..writeByte(6)..write(obj.imageFlag);
  }
}

class SessionStatusAdapter extends TypeAdapter<SessionStatus> {
  @override
  final int typeId = 2;

  @override
  SessionStatus read(BinaryReader reader) {
    return SessionStatus.values[reader.readByte()];
  }

  @override
  void write(BinaryWriter writer, SessionStatus obj) {
    writer.writeByte(obj.index);
  }
}

class SessionAdapter extends TypeAdapter<Session> {
  @override
  final int typeId = 3;

  @override
  Session read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (int i = 0; i < numOfFields; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return Session(
      id: fields[0] as String,
      serverId: fields[1] as String,
      cliToolId: fields[2] as String,
      cliToolCommand: fields[9] as String?,
      tmuxSessionName: fields[3] as String,
      title: fields[4] as String,
      status: fields[5] as SessionStatus? ?? SessionStatus.connecting,
      createdAt: fields[6] as DateTime?,
      lastActiveAt: fields[7] as DateTime?,
      workingDir: fields[8] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Session obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)..write(obj.id)
      ..writeByte(1)..write(obj.serverId)
      ..writeByte(2)..write(obj.cliToolId)
      ..writeByte(3)..write(obj.tmuxSessionName)
      ..writeByte(4)..write(obj.title)
      ..writeByte(5)..write(obj.status)
      ..writeByte(6)..write(obj.createdAt)
      ..writeByte(7)..write(obj.lastActiveAt)
      ..writeByte(8)..write(obj.workingDir)
      ..writeByte(9)..write(obj.cliToolCommand);
  }
}

class MessageRoleAdapter extends TypeAdapter<MessageRole> {
  @override
  final int typeId = 4;

  @override
  MessageRole read(BinaryReader reader) {
    return MessageRole.values[reader.readByte()];
  }

  @override
  void write(BinaryWriter writer, MessageRole obj) {
    writer.writeByte(obj.index);
  }
}

class ChatMessageAdapter extends TypeAdapter<ChatMessage> {
  @override
  final int typeId = 5;

  @override
  ChatMessage read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (int i = 0; i < numOfFields; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return ChatMessage(
      id: fields[0] as String,
      sessionId: fields[1] as String,
      role: fields[2] as MessageRole,
      content: fields[3] as String,
      timestamp: fields[4] as DateTime?,
      imagePaths: (fields[5] as List?)?.cast<String>(),
      isStreaming: fields[6] as bool? ?? false,
    );
  }

  @override
  void write(BinaryWriter writer, ChatMessage obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)..write(obj.id)
      ..writeByte(1)..write(obj.sessionId)
      ..writeByte(2)..write(obj.role)
      ..writeByte(3)..write(obj.content)
      ..writeByte(4)..write(obj.timestamp)
      ..writeByte(5)..write(obj.imagePaths)
      ..writeByte(6)..write(obj.isStreaming);
  }
}
