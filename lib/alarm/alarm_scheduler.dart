import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:flutter/foundation.dart';

import '../core/alarm.dart' as model;
import '../core/schedule.dart';
import '../data/alarm_repository.dart';
import 'plan.dart';
import 'youtube_cache.dart';

/// Keeps the native alarms in step with the stored ones.
///
/// Each enabled alarm gets its next [occurrences] fire times registered, so a weekly alarm keeps
/// ringing for a week even if the app is never opened again.
class AlarmScheduler {
  static const occurrences = 7;
  static const fallbackAsset = 'assets/fallback.wav';

  final AlarmRepository repo;
  final YoutubeCache cache;
  final DateTime Function() _now;

  /// Links whose audio is on the phone, for the list screen.
  final ready = ValueNotifier<Set<String>>({});

  final _tried = <String>{};
  Future<void> _queue = Future.value();

  AlarmScheduler(this.repo, this.cache, {DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  /// Registers the native alarms (serialised), then fetches any missing audio in the background.
  Future<void> sync() {
    _queue = _queue.then((_) => _sync()).catchError((Object e) => debugPrint('sync failed: $e'));
    return _queue;
  }

  Future<void> _sync() async {
    // Re-registering a ringing alarm would silence it.
    if (await Alarm.isRinging()) return;
    final now = _now();
    final alarms = await repo.all();

    final desired = <int, AlarmSettings>{};
    final cached = <String>{};
    final missing = <String>{};
    for (final a in alarms.where((a) => a.enabled)) {
      final path = await cache.cachedPath(a.youtubeUrl);
      if (path != null) cached.add(a.youtubeUrl);
      if (a.youtubeUrl.trim().isNotEmpty && path == null) missing.add(a.youtubeUrl);
      final audio = path ?? a.fallbackPath ?? fallbackAsset;
      var t = nextFire(a.schedule, now);
      for (var k = 0; k < occurrences && t != null; k++) {
        final id = alarmIdFor(a.id, k);
        desired[id] = _settings(a, id, t, audio);
        t = nextFire(a.schedule, t);
      }
    }
    ready.value = cached;

    final existing = await Alarm.getAlarms();
    for (final e in existing) {
      if (e.id != testAlarmId && !desired.containsKey(e.id) && e.dateTime.isAfter(now)) await Alarm.stop(e.id);
    }
    final byId = {for (final e in existing) e.id: e};
    for (final s in desired.values) {
      if (byId[s.id] == s) continue;
      await Alarm.set(alarmSettings: s);
    }

    unawaited(_prefetch(missing));
  }

  Future<void> _prefetch(Set<String> urls) async {
    var any = false;
    for (final url in urls.where(_tried.add)) {
      if (await cache.download(url) == null) any = true;
    }
    if (any) await sync();
  }

  AlarmSettings _settings(model.Alarm a, int id, DateTime at, String audio) {
    final target = a.volume.target;
    return AlarmSettings(
      id: id,
      dateTime: at,
      assetAudioPath: audio,
      loopAudio: true,
      vibrate: false,
      warningNotificationOnKill: false,
      androidFullScreenIntent: true,
      androidStopAlarmOnTermination: false,
      preferConnectedAudioDevice: a.output != model.OutputKind.speaker,
      androidStaleAfter: const Duration(minutes: 10),
      volumeSettings: VolumeSettings.staircaseFade(
        volume: target > 0 ? target : null,
        volumeEnforced: true,
        fadeSteps: [for (final s in fadePlan(a.volume)) VolumeFadeStep(s.time, s.volume)],
      ),
      notificationSettings: NotificationSettings(
        title: a.name,
        body: 'Dậy thôi!',
        stopButton: 'Tắt báo thức',
      ),
    );
  }

  /// Rings [a] in [delay] with its real settings, downloading its audio first. Returns what to tell the user.
  Future<String> testIn(model.Alarm a, Duration delay) async {
    var source = 'nhạc dự phòng (chưa nhập link)';
    var path = a.fallbackPath ?? fallbackAsset;
    if (a.youtubeUrl.trim().isNotEmpty) {
      var cached = await cache.cachedPath(a.youtubeUrl);
      String? error;
      if (cached == null) {
        error = await cache.download(a.youtubeUrl);
        cached = await cache.cachedPath(a.youtubeUrl);
      }
      if (cached != null) {
        path = cached;
        source = 'nhạc YouTube đã tải';
        ready.value = {...ready.value, a.youtubeUrl};
      } else {
        source = 'nhạc dự phòng vì không tải được YouTube ($error)';
      }
    }
    await Alarm.set(alarmSettings: _settings(a, testAlarmId, _now().add(delay), path));
    return 'Sẽ kêu sau ${delay.inSeconds} giây bằng $source.';
  }
}
