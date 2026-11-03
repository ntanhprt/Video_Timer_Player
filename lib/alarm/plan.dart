import '../core/volume_curve.dart';

/// One step of the player-volume fade: from [time] on, play at [volume] (0..1 of the system volume).
typedef FadeStep = ({Duration time, double volume});

/// The system volume is pinned at `spec.target`, so the fade is `volumeAt / target`:
/// it starts at `start/target` and reaches 1.0 (the target) when the ramp ends.
List<FadeStep> fadePlan(VolumeSpec spec) {
  final target = spec.target;
  if (spec.ramp <= Duration.zero || target <= 0) return [(time: Duration.zero, volume: 1.0)];
  final stepMs = (spec.ramp.inMilliseconds ~/ 100).clamp(500, 5000);
  final steps = <FadeStep>[];
  for (var ms = 0; ms < spec.ramp.inMilliseconds; ms += stepMs) {
    final t = Duration(milliseconds: ms);
    steps.add((time: t, volume: (volumeAt(spec, t) / target).clamp(0.0, 1.0).toDouble()));
  }
  steps.add((time: spec.ramp, volume: 1.0));
  return steps;
}

/// Stable 31-bit id for occurrence [k] (0..15) of the alarm [alarmId]: the plugin needs int ids.
int alarmIdFor(String alarmId, int k) {
  assert(k >= 0 && k < 16);
  var h = 0x811c9dc5; // FNV-1a
  for (final c in alarmId.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xffffffff;
  }
  return (((h & 0x3ffffff) << 4) | k) + 16;
}

/// Reserved for the "try it now" button.
const testAlarmId = 1;

/// Picks one of [tracks] for the ring of [alarmId] at [at]: random-looking, or (with
/// `random: false`) the list in order, one track per day.
///
/// Looks random from ring to ring but is a pure function of its inputs, so re-registering the same
/// alarm (every sync) keeps the same pick. Null when there are no tracks.
String? pickTrack(List<String> tracks, String alarmId, DateTime at, {bool random = true}) {
  if (tracks.isEmpty) return null;
  if (!random) {
    // In list order, advancing one track per day.
    final day = DateTime.utc(at.year, at.month, at.day).millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
    return tracks[day % tracks.length];
  }
  var h = 0x811c9dc5;
  for (final c in '$alarmId@${at.millisecondsSinceEpoch ~/ 1000}'.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xffffffff;
  }
  h = (h ^ (h >> 15)) * 0x2c1b3c6d & 0xffffffff;
  return tracks[h % tracks.length];
}
