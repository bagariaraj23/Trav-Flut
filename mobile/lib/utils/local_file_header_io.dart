import 'dart:io';

/// First bytes of a local file, used for MIME sniffing. Null when unreadable.
List<int>? readLocalFileHeader(String path) {
  try {
    final file = File(path).openSync();
    try {
      return file.readSync(12);
    } finally {
      file.closeSync();
    }
  } catch (_) {
    return null;
  }
}
