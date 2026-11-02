/// Shape of the volume ramp from [VolumeSpec.start] to [VolumeSpec.target].
enum RampCurve { linear, easeIn, easeOut }

class VolumeSpec {
  /// Volumes are fractions in 0.0–1.0.
  final double start;
  final double target;
  final Duration ramp;
  final RampCurve curve;

  /// How long the alarm keeps playing before it stops itself.
  final Duration hold;

  const VolumeSpec({
    this.start = 0.0,
    this.target = 0.7,
    this.ramp = const Duration(seconds: 60),
    this.curve = RampCurve.easeIn,
    this.hold = const Duration(minutes: 30),
  });

  Map<String, dynamic> toJson() => {
        'start': start,
        'target': target,
        'rampSeconds': ramp.inSeconds,
        'curve': curve.name,
        'holdSeconds': hold.inSeconds,
      };

  factory VolumeSpec.fromJson(Map<String, dynamic> j) => VolumeSpec(
        start: (j['start'] as num).toDouble(),
        target: (j['target'] as num).toDouble(),
        ramp: Duration(seconds: j['rampSeconds'] as int),
        curve: RampCurve.values.byName(j['curve'] as String),
        hold: Duration(seconds: j['holdSeconds'] as int),
      );
}

/// Player volume (0.0–1.0) [elapsed] after the alarm started.
///
/// Equals `start` at 0, `target` from `ramp` onwards, never decreases for a
/// valid spec (target >= start).
double volumeAt(VolumeSpec v, Duration elapsed) {
  if (elapsed <= Duration.zero) return v.start;
  if (v.ramp <= Duration.zero || elapsed >= v.ramp) return v.target;
  final t = elapsed.inMicroseconds / v.ramp.inMicroseconds;
  final shaped = switch (v.curve) {
    RampCurve.linear => t,
    RampCurve.easeIn => t * t,
    RampCurve.easeOut => 1 - (1 - t) * (1 - t),
  };
  return (v.start + (v.target - v.start) * shaped).clamp(0.0, 1.0).toDouble();
}
