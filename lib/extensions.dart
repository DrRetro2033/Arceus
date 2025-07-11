import 'dart:convert';
import 'dart:io';
import 'package:hashlib/hashlib.dart';
// import 'package:arceus/scripting/addon.dart';

/// # `extension` Compression
/// ## Extension for the `String` class.
/// Used to compress and decompress strings.
extension Pathing on String {
  /// Fixes the path by converting windows formatting to an absolute path in unix format.
  /// This will also replace environment variables with their values.
  String fixPath() {
    String path = replaceAll("\"", "");
    path = path.replaceAll("\\", "/");
    if (Platform.isWindows) {
      /// Replace environment variables to absolute paths on Windows
      RegExp envVar = RegExp(r"(?:%(\w*)%)");
      for (RegExpMatch match in envVar.allMatches(path)) {
        path = path.replaceFirst(
            match.group(0)!, Platform.environment[match.group(1)!]!.fixPath());
      }
    }
    if (path.startsWith("/")) path = path.substring(1);
    return path;
  }

  String relativeTo(String relativeTo) {
    final formattedPath = fixPath();
    final formattedRelativeTo = relativeTo.fixPath();
    return formattedPath.replaceFirst(formattedRelativeTo, "").fixPath();
  }

  /// # `String` getFilename()
  /// ## Returns the filename of the string.
  /// The filename will be the same for both internal and external paths.
  String getFilename({bool withExtension = true}) {
    String path = fixPath();
    if (withExtension) {
      return path.split("/").last;
    } else {
      return path.split("/").last.split(".").first;
    }
  }

  String formatForXML() {
    return replaceAll(RegExp("'\""), "");
  }
}

extension ChunkStream on Stream<int> {
  Stream<List<int>> chunk(int chunkSize) async* {
    final List<int> buffer = [];
    await for (int byte in this) {
      buffer.add(byte);
      if (buffer.length == chunkSize) {
        yield buffer;
        buffer.clear();
      }
    }
    if (buffer.isNotEmpty) {
      yield buffer;
    }
  }
}

extension CreateParentDirectory on File {
  Future<void> ensureParentDirectory() async {
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    return;
  }
}

extension FileChecksum on File {
  Future<String> get checksum async => md5sum(await openRead()
      .transform(gzip.encoder)
      .transform(base64.encoder)
      .reduce((a, b) => a + b));
}

extension DirectoryChecksum on Directory {
  Future<String> get checksum async {
    List<String> checksums = [];
    await for (final file in list(recursive: true)) {
      if (file is File) {
        checksums.add(await file.checksum);
      }
    }
    return md5sum(checksums.join());
  }
}
