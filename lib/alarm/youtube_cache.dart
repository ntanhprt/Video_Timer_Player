import 'dart:io';

import 'package:flutter/foundation.dart';
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

  Future<File> _file(String url) async {
    final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'audio'));
    await dir.create(recursive: true);
    return File(p.join(dir.path, '${_hash(url)}.m4a'));
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

  /// Downloads the audio of [url]. Returns null on success, otherwise a short reason.
  Future<String?> download(String url) async {
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
          final manifest = await yt.videos.streams.getManifest(id, ytClients: [client]);
          final audio = manifest.audioOnly;
          final mp4 = audio.where((s) => s.container == StreamContainer.mp4);
          final info = (mp4.isNotEmpty ? mp4 : audio).withHighestBitrate();
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
