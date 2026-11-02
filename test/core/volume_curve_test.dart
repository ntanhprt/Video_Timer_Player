import 'package:flutter_test/flutter_test.dart';
import 'package:video_timer_player/core/volume_curve.dart';

VolumeSpec spec(RampCurve c, {double start = 0.0, Duration ramp = const Duration(seconds: 30)}) =>
    VolumeSpec(start: start, target: 0.8, ramp: ramp, curve: c, hold: const Duration(minutes: 30));

void main() {
  test('starts at start volume', () {
    expect(volumeAt(spec(RampCurve.linear), Duration.zero), 0.0);
    expect(volumeAt(spec(RampCurve.linear, start: 0.2), Duration.zero), 0.2);
  });

  test('reaches target exactly at ramp end', () {
    expect(volumeAt(spec(RampCurve.linear), const Duration(seconds: 30)), 0.8);
    expect(volumeAt(spec(RampCurve.easeIn), const Duration(seconds: 30)), 0.8);
  });

  test('linear midpoint is halfway', () {
    expect(volumeAt(spec(RampCurve.linear), const Duration(seconds: 15)), closeTo(0.4, 1e-9));
  });

  test('easeIn is below linear at midpoint, easeOut above', () {
    const mid = Duration(seconds: 15);
    final ein = volumeAt(spec(RampCurve.easeIn), mid);
    final eout = volumeAt(spec(RampCurve.easeOut), mid);
    expect(ein, greaterThan(0.0));
    expect(ein, lessThan(0.4));
    expect(eout, greaterThan(0.4));
    expect(eout, lessThan(0.8));
  });

  test('never exceeds target after the ramp', () {
    expect(volumeAt(spec(RampCurve.easeIn), const Duration(minutes: 10)), 0.8);
  });

  test('is monotonic non-decreasing for every curve', () {
    for (final c in RampCurve.values) {
      var prev = -1.0;
      for (var s = 0; s <= 40; s++) {
        final v = volumeAt(spec(c), Duration(seconds: s));
        expect(v, greaterThanOrEqualTo(prev), reason: '${c.name} at ${s}s');
        expect(v, inInclusiveRange(0.0, 1.0));
        prev = v;
      }
    }
  });

  test('zero ramp returns target immediately', () {
    expect(volumeAt(spec(RampCurve.linear, ramp: Duration.zero), Duration.zero), 0.8);
  });

  test('negative elapsed clamps to start', () {
    expect(volumeAt(spec(RampCurve.linear, start: 0.1), const Duration(seconds: -5)), 0.1);
  });
}
