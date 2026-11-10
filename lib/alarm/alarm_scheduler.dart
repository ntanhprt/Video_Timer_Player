import 'dart:async';
import 'dart:io';

import 'package:alarm/alarm.dart';
import 'package:flutter/foundation.dart';

import '../core/alarm.dart' as model;
import '../core/schedule.dart';
import '../data/alarm_repository.dart';
import 'alarm_health.dart';
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

  /// More native alarms to keep registered (the Tuya timers), by id.
  final Map<int, AlarmSettings> Function(DateTime now)? extraAlarms;

  /// Permissions the phone has not granted that make the alarm unreliable.
  final Future<Set<AlarmProblem>> Function()? permissionProblems;

  /// What is wrong with the alarm right now, for the list screen. Updated by `sync(audit: true)`.
  final health = ValueNotifier<AlarmHealth>(AlarmHealth.ok);

  AlarmScheduler(this.repo, this.cache, {DateTime Function()? clock, this.extraAlarms, this.permissionProblems}) : _now = clock ?? DateTime.now;

  /// The user has read the "alarms were wiped" notice.
  void dismissWiped() => health.value = health.value.without(AlarmProblem.wiped);

  /// Registers the native alarms (serialised), then fetches any missing audio in the background.
  ///
  /// With [audit], first compares what Android has registered with what should be, so a wipe by
  /// the system is noticed. Use it only when the app starts or comes back to the front: right after
  /// an edit the new alarm is legitimately not registered yet.
  Future<void> sync({bool audit = false}) {
    _queue = _queue.then((_) => _sync(audit: audit)).catchError((Object e) => debugPrint('sync failed: $e'));
    return _queue;
  }

  Future<void> _audit(Set<int> expected, List<AlarmSettings> existing) async {
    final problems = await permissionProblems?.call() ?? const <AlarmProblem>{};
    health.value = assessHealth(
      expected: expected,
      registered: {for (final e in existing) e.id},
      permissionProblems: problems,
      previous: health.value,
    );
  }

  Future<void> _sync({bool audit = false}) async {
    // Re-registering a ringing alarm would silence it.
    if (await Alarm.isRinging()) return;
    final now = _now();
    final alarms = await repo.all();

    final desired = <int, AlarmSettings>{};
    final cached = <String>{};
    final missing = <String>{};
    for (final a in alarms.where((a) => a.enabled)) {
      final paths = <String>[];
      for (final url in a.youtubeUrls.where((u) => u.trim().isNotEmpty)) {
        final path = await cache.cachedPath(url);
        if (path == null) {
          missing.add(url);
        } else {
          cached.add(url);
          paths.add(path);
        }
      }
      for (final f in a.audioFiles) {
        if (await File(f).exists()) paths.add(f);
      }
      var t = nextFire(a.schedule, now);
      for (var k = 0; k < occurrences && t != null; k++) {
        final id = alarmIdFor(a.id, k);
        final audio = pickTrack(paths, a.id, t, random: a.randomOrder) ?? a.fallbackPath ?? fallbackAsset;
        desired[id] = _settings(a, id, t, audio);
        t = nextFire(a.schedule, t);
      }
    }
    desired.addAll(extraAlarms?.call(now) ?? const {});
    ready.value = cached;

    final existing = await Alarm.getAlarms();
    if (audit) await _audit(desired.keys.toSet(), existing);
    for (final e in existing) {
      if (e.id != testAlarmId && e.id != snoozeAlarmId && !desired.containsKey(e.id) && e.dateTime.isAfter(now)) await Alarm.stop(e.id);
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
      final error = await cache.download(url);
      if (error == null) {
        any = true;
      } else if (cache.rateLimited) {
        // Not this link's fault: let a later sync (e.g. on app resume) try it again.
        _tried.remove(url);
        break;
      }
    }
    if (any) await sync();
  }

  AlarmSettings _settings(model.Alarm a, int id, DateTime at, String audio) {
    final target = a.volume.target;
    return AlarmSettings(
      id: id,
      dateTime: at,
      assetAudioPath: audio,
      payload: holdPayload(a.volume.hold),
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

  /// Downloads every link now, reporting each step to [log]. Returns a one-line summary.
  Future<String> downloadNow(List<String> urls, {required void Function(String) log}) async {
    final list = urls.where((u) => u.trim().isNotEmpty).toList();
    if (list.isEmpty) return 'Chưa có link nào để tải.';
    var ok = 0;
    for (var i = 0; i < list.length; i++) {
      final url = list[i];
      log('[${i + 1}/${list.length}] $url');
      if (await cache.cachedPath(url) != null) {
        log('Đã có trong máy, bỏ qua.');
        ok++;
        continue;
      }
      final error = await cache.download(url, log: log);
      if (error == null && await cache.cachedPath(url) != null) {
        ok++;
        ready.value = {...ready.value, url};
        log('Xong.');
      } else {
        log('THẤT BẠI: ${error ?? 'không tạo được file'}');
      }
    }
    unawaited(sync());
    return 'Tải được $ok/${list.length} bài.';
  }

  /// Rings [a] in [delay] with its real settings, using one of its tracks (downloading it first
  /// if needed). Returns what to tell the user.
  Future<String> testIn(model.Alarm a, Duration delay, {void Function(String)? log}) async {
    final say = log ?? (_) {};
    var source = 'nhạc dự phòng (chưa có bài nào)';
    var path = a.fallbackPath ?? fallbackAsset;
    final urls = a.youtubeUrls.where((u) => u.trim().isNotEmpty).toList();
    final candidates = <String>[...urls, ...a.audioFiles];
    if (a.randomOrder) candidates.shuffle();
    final errors = <String>[];
    say(candidates.isEmpty ? 'Chưa có link hay file nào: dùng nhạc dự phòng.' : 'Có ${urls.length} link + ${a.audioFiles.length} file, ${a.randomOrder ? 'chọn ngẫu nhiên' : 'lấy bài đầu tiên dùng được (chế độ theo thứ tự)'}.');
    for (final c in candidates) {
      if (!urls.contains(c)) {
        say('File trong máy: $c');
        if (await File(c).exists()) {
          path = c;
          source = 'file trong máy';
          break;
        }
        say('File không còn tồn tại, bỏ qua.');
        continue;
      }
      say('Link: $c');
      var cached = await cache.cachedPath(c);
      if (cached == null) {
        say('Chưa có trong máy, tải về...');
        final error = await cache.download(c, log: say);
        if (error != null) errors.add('$c -> $error');
        cached = await cache.cachedPath(c);
      }
      if (cached != null) {
        say('Đã có file âm thanh: $cached');
        path = cached;
        source = 'bài YouTube đã tải ($c)';
        ready.value = {...ready.value, c};
        break;
      }
      source = 'nhạc dự phòng vì không tải được';
    }
    say('Hẹn giờ kêu sau ${delay.inSeconds} giây (${path == fallbackAsset ? 'nhạc dự phòng' : source})...');
    await Alarm.set(alarmSettings: _settings(a, testAlarmId, _now().add(delay), path));
    final detail = errors.isEmpty ? '' : '\nLỗi: ${errors.join('\n')}';
    return 'Sẽ kêu sau ${delay.inSeconds} giây bằng $source.$detail';
  }
}
