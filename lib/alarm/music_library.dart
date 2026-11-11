import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'youtube_cache.dart';

/// Folder of the audio files picked from the phone, copied in so they outlive the original.
Future<Directory> musicDirectory() async {
  final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'music'));
  await dir.create(recursive: true);
  return dir;
}

/// One audio file on the phone that any alarm can play.
typedef LibraryTrack = ({String path, String name, String? url, int bytes, DateTime modified, bool youtube});

/// Every audio file the app keeps on the phone, whichever alarm brought it: the YouTube audio
/// already downloaded and the files picked from storage. Alarms share it instead of each owning
/// its own copy.
class MusicLibrary {
  final YoutubeCache cache;
  final Future<Directory> Function() _musicDir;

  MusicLibrary(this.cache, {Future<Directory> Function()? musicDir}) : _musicDir = musicDir ?? musicDirectory;

  static Future<String?> _read(String path) async {
    try {
      final f = File(path);
      if (!await f.exists()) return null;
      final t = (await f.readAsString()).trim();
      return t.isEmpty ? null : t;
    } catch (_) {
      return null;
    }
  }

  /// Newest first. [knownUrls] (the links of all alarms) name downloads made before the link was
  /// saved next to the audio.
  Future<List<LibraryTrack>> all({Iterable<String> knownUrls = const []}) async {
    final byKey = {for (final u in knownUrls) YoutubeCache.keyOf(u): u.trim()};
    final out = <LibraryTrack>[];

    final audio = await cache.audioDirectory();
    await for (final e in audio.list()) {
      // `.part` files are downloads still in progress.
      if (e is! File || !e.path.endsWith('.m4a') || e.path.contains('.part')) continue;
      final stat = await e.stat();
      if (stat.size == 0) continue;
      final url = await _read('${e.path}.url') ?? byKey[p.basenameWithoutExtension(e.path)];
      final title = await _read('${e.path}.title');
      out.add((path: e.path, name: title ?? url ?? 'Bài YouTube đã tải', url: url, bytes: stat.size, modified: stat.modified, youtube: true));
    }

    final music = await _musicDir();
    await for (final e in music.list()) {
      if (e is! File) continue;
      final stat = await e.stat();
      if (stat.size == 0) continue;
      out.add((path: e.path, name: p.basename(e.path).replaceFirst(RegExp(r'^\d+_'), ''), url: null, bytes: stat.size, modified: stat.modified, youtube: false));
    }

    out.sort((a, b) => b.modified.compareTo(a.modified));
    return out;
  }
}
