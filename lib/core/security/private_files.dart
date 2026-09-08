import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PrivateFiles {
  static Future<Directory> createSessionDirectory() async {
    final Directory root = await getTemporaryDirectory();
    await root.create(recursive: true);
    final Directory directory = await root.createTemp('zerotype_private_');
    if (Platform.isMacOS || Platform.isLinux) {
      final ProcessResult result = await Process.run('/bin/chmod', [
        '700',
        directory.path,
      ]);
      if (result.exitCode != 0)
        throw FileSystemException(
          'Cannot protect temporary directory',
          directory.path,
        );
    }
    return directory;
  }

  /// Only reclaim stale owned files, leaving other active app instances alone.
  static Future<void> purgeStaleTemporaryFiles() async {
    final Directory root = await getTemporaryDirectory();
    if (!await root.exists()) return;
    final DateTime cutoff = DateTime.now().subtract(const Duration(days: 1));
    await for (final FileSystemEntity entry in root.list(followLinks: false)) {
      final String name = p.basename(entry.path);
      final bool isOwned =
          (entry is Directory && name.startsWith('zerotype_private_')) ||
          (entry is File && RegExp(r'^zerotype_\d+\.m4a$').hasMatch(name));
      if (isOwned && (await entry.stat()).modified.isBefore(cutoff)) {
        await entry.delete(recursive: entry is Directory);
      }
    }
  }

  static Future<void> writeAtomically(File file, List<int> bytes) async {
    await file.parent.create(recursive: true);
    final File temporary = File('${file.path}.tmp');
    if (await FileSystemEntity.type(temporary.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const FileSystemException('Refusing symbolic link');
    }
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(file.path);
  }
}
