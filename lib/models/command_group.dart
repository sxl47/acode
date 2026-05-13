import 'package:hive/hive.dart';

class CommandGroup {
  final String id;
  String name;
  List<String> commands;

  CommandGroup({
    required this.id,
    required this.name,
    required this.commands,
  });

  static List<CommandGroup> defaults() {
    return [
      CommandGroup(
        id: 'git',
        name: 'Git',
        commands: [
          'git status',
          'git add .',
          'git commit -m ""',
          'git push',
          'git pull --rebase',
          'git log --oneline',
          'git branch -a',
          'git checkout',
          'git diff',
          'git stash',
          'git stash pop',
        ],
      ),
      CommandGroup(
        id: 'tmux',
        name: 'Tmux',
        commands: [
          'tmux ls',
          'tmux new -s mysession',
          'tmux detach',
          'tmux kill-session -t ',
          'tmux rename-session -t ',
        ],
      ),
      CommandGroup(
        id: 'docker',
        name: 'Docker',
        commands: [
          'docker ps',
          'docker images',
          'docker logs -f ',
          'docker exec -it  bash',
          'docker compose up',
          'docker compose down',
          'docker system df',
        ],
      ),
      CommandGroup(
        id: 'file',
        name: 'File',
        commands: [
          'ls -la',
          'pwd',
          'cat ',
          'grep -rn "" .',
          'find . -name ""',
          'nano ',
          'tail -f ',
          'chmod +x ',
          'mv  ',
          'cp -r  ',
          'rm -rf ',
          'mkdir -p ',
          'du -sh */',
        ],
      ),
      CommandGroup(
        id: 'system',
        name: 'System',
        commands: [
          'htop',
          'df -h',
          'free -h',
          'whoami',
          'uname -a',
          'lsof -i :',
          'ps aux',
          'kill -9 ',
          'nc -zv  ',
          'ping ',
        ],
      ),
    ];
  }
}

class CommandGroupAdapter extends TypeAdapter<CommandGroup> {
  @override
  final int typeId = 6;

  @override
  CommandGroup read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (int i = 0; i < numOfFields; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return CommandGroup(
      id: fields[0] as String,
      name: fields[1] as String,
      commands: (fields[2] as List).cast<String>(),
    );
  }

  @override
  void write(BinaryWriter writer, CommandGroup obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.commands);
  }
}
