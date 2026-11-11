import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Audio of YouTube links, downloaded ahead of time so the alarm only plays a local file.
///
/// Extracting audio is against YouTube's terms; this is for personal use only.
class YoutubeCache {
  static const rateLimitCooldown = Duration(minutes: 15);

  /// While set and in the future, YouTube has just rate-limited us and downloads are skipped.
  DateTime? _blockedUntil;

  /// Whether [download] is currently skipping because of a rate limit.
  bool get rateLimited => _blockedUntil?.isAfter(DateTime.now()) ?? false;

  final Future<Directory> Function()? _dir;

  YoutubeCache({Future<Directory> Function()? dir}) : _dir = dir;

  /// Where the downloaded audio lives.
  Future<Directory> audioDirectory() async {
    final dir = _dir != null ? await _dir() : Directory(p.join((await getApplicationSupportDirectory()).path, 'audio'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> _file(String url) async => File(p.join((await audioDirectory()).path, '${keyOf(url)}.m4a'));

  /// File name (without extension) the audio of [url] is stored under.
  static String keyOf(String url) => _hash(url);

  /// Saves the link next to the audio so the file can be listed and reused without knowing it.
  Future<void> _remember(String url) async {
    try {
      await File('${(await _file(url)).path}.url').writeAsString(url.trim());
    } catch (e) {
      debugPrint('YT could not save link: $e');
    }
  }

  static String _hash(String s) {
    var h = 0x811c9dc5;
    for (final c in s.trim().codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16);
  }

  /// Path of the downloaded audio for [url], or null when not downloaded.
  Future<String?> cachedPath(String url) async {
    if (url.trim().isEmpty) return null;
    final f = await _file(url);
    return await f.exists() && await f.length() > 0 ? f.path : null;
  }

  /// Title of the video behind [url] (saved next to the audio when it was downloaded), or null.
  Future<String?> title(String url) async {
    try {
      final f = File('${(await _file(url)).path}.title');
      if (!await f.exists()) return null;
      final t = (await f.readAsString()).trim();
      return t.isEmpty ? null : t;
    } catch (_) {
      return null;
    }
  }

  /// Downloads the audio of [url]. Returns null on success, otherwise a short reason.
  ///
  /// Each step is reported to [log] as it happens.
  Future<String?> download(String url, {void Function(String)? log}) async {
    final say = log ?? (_) {};
    say('Tải bằng yt-dlp (lần đầu phải giải nén, có thể mất vài chục giây)...');
    final viaYtDlp = await _ytDlp(url, say);
    if (viaYtDlp == null) {
      say('yt-dlp: tải xong.');
      await _remember(url);
      return null;
    }
    say('yt-dlp lỗi: $viaYtDlp');
    say('Thử cách dự phòng (youtube_explode)...');
    final viaExplode = await _explode(url, say);
    if (viaExplode == null) {
      say('youtube_explode: tải xong.');
      await _remember(url);
      return null;
    }
    say('youtube_explode lỗi: $viaExplode');
    return 'yt-dlp: $viaYtDlp\nexplode: $viaExplode';
  }

  static const _channel = MethodChannel('vn.aisolutions/ytdlp');
  void Function(String)? _progress;

  /// yt-dlp bundled in the app (the same engine other downloader apps use). Null on success.
  Future<String?> _ytDlp(String url, void Function(String) say) async {
    _progress = say;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'log') _progress?.call(call.arguments as String);
    });
    try {
      final target = await _file(url);
      final tmp = '${target.path}.part.m4a';
      await _channel.invokeMethod<String>('download', {'url': url.trim(), 'out': tmp, 'titleOut': '${target.path}.title'});
      await File(tmp).rename(target.path);
      return null;
    } on PlatformException catch (e) {
      debugPrint('YT yt-dlp failed [${e.message}]');
      return e.message ?? 'không rõ lỗi';
    } on MissingPluginException {
      return 'yt-dlp không có trong bản này';
    } catch (e) {
      debugPrint('YT yt-dlp failed [$e]');
      return '$e';
    }
  }

  Future<String?> _explode(String url, void Function(String) say) async {
    final wait = _blockedUntil?.difference(DateTime.now());
    if (wait != null && !wait.isNegative) {
      return 'YouTube đang giới hạn tốc độ từ mạng này, tự thử lại sau ~${wait.inMinutes + 1} phút';
    }
    final yt = YoutubeExplode();
    String? lastError;
    try {
      final id = VideoId(url.trim());
      final clients = {
        'androidSdkless': YoutubeApiClient.androidSdkless,
        'androidVr': YoutubeApiClient.androidVr,
        'tv': YoutubeApiClient.tv,
      };
      for (final entry in clients.entries) {
        final client = entry.value;
        try {
          say('Kiểu kết nối ${entry.key}: lấy thông tin video...');
          final manifest = await yt.videos.streams.getManifest(id, ytClients: [client]);
          final audio = manifest.audioOnly;
          final mp4 = audio.where((s) => s.container == StreamContainer.mp4);
          final info = (mp4.isNotEmpty ? mp4 : audio).withHighestBitrate();
          say('${entry.key}: đang tải âm thanh...');
          final target = await _file(url);
          final tmp = File('${target.path}.part');
          final sink = tmp.openWrite();
          try {
            await yt.videos.streams.get(info).pipe(sink);
          } finally {
            await sink.close();
          }
          await tmp.rename(target.path);
          return null;
        } on RequestLimitExceededException catch (e) {
          // Retrying with other clients only makes the block last longer: back off.
          debugPrint('YT rate limited [${entry.key}]: $e');
          _blockedUntil = DateTime.now().add(rateLimitCooldown);
          return 'YouTube đang giới hạn tốc độ từ mạng này (quá nhiều yêu cầu). '
              'Đợi ${rateLimitCooldown.inMinutes} phút rồi thử lại; app cũng tự thử lại.';
        } catch (e) {
          lastError = '${entry.key}: $e';
          debugPrint('YT download failed [$lastError]');
        }
      }
      return lastError ?? 'không rõ lỗi';
    } catch (e) {
      debugPrint('YT bad link: $e');
      return 'liên kết không đọc được: $e';
    } finally {
      yt.close();
    }
  }
}
