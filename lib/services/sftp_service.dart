import 'dart:io';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import 'ssh_service.dart';

class SftpService {
  final SshService _ssh;
  static const String _uploadDir = '~/acode-uploads';

  SftpService(this._ssh);

  Future<SftpClient> _getClient() async {
    return await _ssh.getSftp();
  }

  Future<void> ensureUploadDir() async {
    await _ssh.exec('mkdir -p $_uploadDir');
  }

  Future<String> uploadFile(File localFile, String remoteName) async {
    final sftp = await _getClient();
    await ensureUploadDir();

    final remotePath = '$_uploadDir/$remoteName';
    final data = await localFile.readAsBytes();

    final file = await sftp.open(
      remotePath,
      mode: SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.truncate,
    );

    try {
      await file.writeBytes(data);
    } finally {
      await file.close();
    }

    return remotePath;
  }

  Future<String> uploadBytes(Uint8List data, String remoteName) async {
    final sftp = await _getClient();
    await ensureUploadDir();

    final remotePath = '$_uploadDir/$remoteName';
    final file = await sftp.open(
      remotePath,
      mode: SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.truncate,
    );

    try {
      await file.writeBytes(data);
    } finally {
      await file.close();
    }

    return remotePath;
  }

  Future<void> deleteFile(String remotePath) async {
    final sftp = await _getClient();
    await sftp.remove(remotePath);
  }

  Future<void> cleanupOld({Duration maxAge = const Duration(days: 7)}) async {
    await _ssh.exec(
      "find $_uploadDir -type f -mtime +${maxAge.inDays} -delete 2>/dev/null || true",
    );
  }
}
