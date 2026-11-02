import 'package:flutter_test/flutter_test.dart';
import 'package:video_timer_player/alarm/plan.dart';
import 'package:video_timer_player/core/volume_curve.dart';

void main() {
  group('fadePlan', () {
    const spec = VolumeSpec(start: 0.1, target: 0.8, ramp: Duration(seconds: 30), curve: RampCurve.linear);

    test('starts at start/target, ends at 1.0 exactly when the ramp ends', () {
      final p = fadePlan(spec);
      expect(p.first.time, Duration.zero);
      expect(p.first.volume, closeTo(0.1 / 0.8, 1e-9));
      expect(p.last.time, const Duration(seconds: 30));
      expect(p.last.volume, 1.0);
    });

    test('times strictly increase and volume never decreases', () {
      final p = fadePlan(spec);
      for (var i = 1; i < p.length; i++) {
        expect(p[i].time, greaterThan(p[i - 1].time));
        expect(p[i].volume, greaterThanOrEqualTo(p[i - 1].volume));
      }
    });

    test('zero ramp is one step at full volume', () {
      expect(fadePlan(const VolumeSpec(ramp: Duration.zero)), [(time: Duration.zero, volume: 1.0)]);
    });

    test('a long ramp stays within a few hundred steps', () {
      expect(fadePlan(const VolumeSpec(ramp: Duration(seconds: 300))).length, lessThan(200));
    });
  });

  group('alarmIdFor', () {
    test('is stable, positive, fits 31 bits, and differs per occurrence', () {
      final ids = {for (var k = 0; k < 16; k++) alarmIdFor('abc', k)};
      expect(ids, hasLength(16));
      expect(alarmIdFor('abc', 3), alarmIdFor('abc', 3));
      for (final id in ids) {
        expect(id, inInclusiveRange(16, 0x7fffffff));
      }
      expect(alarmIdFor('abc', 0), isNot(alarmIdFor('abd', 0)));
    });
  });
}
