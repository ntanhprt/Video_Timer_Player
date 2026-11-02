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
