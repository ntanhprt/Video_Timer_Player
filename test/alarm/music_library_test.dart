import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:video_timer_player/alarm/music_library.dart';
import 'package:video_timer_player/alarm/youtube_cache.dart';

void main() {
  late Directory root;
  late Directory audio;
  late Directory music;
  late MusicLibrary lib;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('music_library_test');
    audio = Directory(p.join(root.path, 'audio'));
    music = Directory(p.join(root.path, 'music'));
    await music.create();
    lib = MusicLibrary(YoutubeCache(dir: () async => audio), musicDir: () async => music);
  });

  tearDown(() => root.delete(recursive: true));

  Future<File> write(String path, [String text = 'x']) async {
    final f = File(path);
    await f.parent.create(recursive: true);
    return f.writeAsString(text);
  }

  test('empty phone, empty library', () async {
    expect(await lib.all(), isEmpty);
  });

  test('lists downloaded YouTube audio with its title and link', () async {
    const url = 'https://youtu.be/abc';
    final f = await write(p.join(audio.path, '${YoutubeCache.keyOf(url)}.m4a'), 'audio');
    await write('${f.path}.title', 'Bài hát hay\n');
    await write('${f.path}.url', url);
    final all = await lib.all();
    expect(all, hasLength(1));
    expect(all.single.name, 'Bài hát hay');
    expect(all.single.url, url);
    expect(all.single.youtube, isTrue);
    expect(all.single.path, f.path);
    expect(all.single.bytes, 5);
  });

  test('an older download without the saved link is named by the alarms that use it', () async {
    const url = 'https://youtu.be/old';
    await write(p.join(audio.path, '${YoutubeCache.keyOf(url)}.m4a'));
    expect((await lib.all()).single.url, isNull);
    expect((await lib.all(knownUrls: [' $url '])).single.url, url);
  });

  test('skips unfinished downloads, empty files and the side files', () async {
    await write(p.join(audio.path, 'a.m4a.part.m4a'));
    await write(p.join(audio.path, 'b.m4a.part'));
    await write(p.join(audio.path, 'c.m4a'), '');
    await write(p.join(audio.path, 'c.m4a.title'), 'only a title');
    expect(await lib.all(), isEmpty);
  });

  test('includes files picked from storage, without the numeric prefix', () async {
    await write(p.join(music.path, '1730000000000_Sáng sớm.mp3'));
    final all = await lib.all();
    expect(all.single.name, 'Sáng sớm.mp3');
    expect(all.single.youtube, isFalse);
    expect(all.single.url, isNull);
  });

  test('newest first across both sources', () async {
    final old = await write(p.join(music.path, '1_old.mp3'));
    await old.setLastModified(DateTime(2026, 1, 1));
    final fresh = await write(p.join(audio.path, 'fresh.m4a'));
    await fresh.setLastModified(DateTime(2026, 11, 1));
    expect([for (final t in await lib.all()) t.path], [fresh.path, old.path]);
  });
}
