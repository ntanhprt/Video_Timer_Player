import 'package:flutter_test/flutter_test.dart';
import 'package:video_timer_player/core/alarm.dart';
import 'package:video_timer_player/core/schedule.dart';
import 'package:video_timer_player/core/validation.dart';
import 'package:video_timer_player/core/volume_curve.dart';

const goodUrl = 'https://youtu.be/dQw4w9WgXcQ';

Alarm make({
  ScheduleSpec? schedule,
  String url = goodUrl,
  VolumeSpec volume = const VolumeSpec(),
}) =>
    Alarm(
      id: 'a1',
      name: 'Sáng',
      schedule: schedule ?? Weekly(const TimeOfDayMin(6, 30), {1, 2, 3, 4, 5, 6, 7}),
      youtubeUrl: url,
      volume: volume,
      output: OutputKind.anyConnected,
      enabled: true,
      rev: 1,
      updatedAt: DateTime.utc(2026, 11, 2),
    );

VolumeSpec vol({double start = 0, double target = 0.7, int rampS = 60, int holdMin = 30}) => VolumeSpec(
      start: start,
      target: target,
      ramp: Duration(seconds: rampS),
      curve: RampCurve.easeIn,
      hold: Duration(minutes: holdMin),
    );

void main() {
  test('spec defaults are valid and match the spec values', () {
    const v = VolumeSpec();
    expect([v.start, v.target, v.ramp, v.curve, v.hold],
        [0.0, 0.7, const Duration(seconds: 60), RampCurve.easeIn, const Duration(minutes: 30)]);
    expect(validate(make()), isEmpty);
  });

  test('target below start -> exactly one error', () {
    final e = validate(make(volume: vol(start: 0.6, target: 0.3)));
    expect(e, hasLength(1));
    expect(e.single, contains('đích'));
  });

  test('target 0 -> exactly one error', () {
    final e = validate(make(volume: vol(start: 0, target: 0)));
    expect(e, hasLength(1));
    expect(e.single, contains('không có tiếng'));
  });

  test('volume outside 0..1 -> error', () {
    expect(validate(make(volume: vol(target: 1.5))), hasLength(1));
  });

  test('negative ramp -> exactly one error', () {
    final e = validate(make(volume: vol(rampS: -1)));
    expect(e, hasLength(1));
    expect(e.single, contains('không được âm'));
  });

  test('ramp longer than hold -> exactly one error', () {
    final e = validate(make(volume: vol(rampS: 31 * 60, holdMin: 30)));
    expect(e, hasLength(1));
    expect(e.single, contains('dài hơn'));
  });

  test('non-YouTube URL -> exactly one error; empty URL is allowed', () {
    final e = validate(make(url: 'https://example.com/video'));
    expect(e, hasLength(1));
    expect(e.single, contains('YouTube'));
    expect(validate(make(url: 'not a url')), hasLength(1));
    expect(validate(make(url: '')), isEmpty);
    expect(validate(make(url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ')), isEmpty);
    expect(validate(make(url: 'https://m.youtube.com/watch?v=dQw4w9WgXcQ')), isEmpty);
  });

  test('empty weekday set -> exactly one error for Weekly, Windowed and Staged', () {
    final weekly = make(schedule: Weekly(const TimeOfDayMin(6, 30), {}));
    final win = make(schedule: Windowed(const TimeOfDayMin(6, 0), const TimeOfDayMin(7, 0), const Duration(minutes: 10), {}));
    final staged = make(schedule: Staged(start: const TimeOfDayMin(6, 0), weekdays: {}, stages: [Stage(offset: Duration.zero, volume: const VolumeSpec())]));
    for (final a in [weekly, win, staged]) {
      final e = validate(a);
      expect(e, hasLength(1), reason: a.schedule.runtimeType.toString());
      expect(e.single, contains('ít nhất một ngày'));
    }
  });

  test('Windowed needs interval >= 1 minute and from <= to', () {
    final zero = make(schedule: Windowed(const TimeOfDayMin(6, 0), const TimeOfDayMin(7, 0), Duration.zero, {1}));
    final reversed = make(schedule: Windowed(const TimeOfDayMin(8, 0), const TimeOfDayMin(7, 0), const Duration(minutes: 5), {1}));
    expect(validate(zero), hasLength(1));
    expect(validate(reversed), hasLength(1));
  });

  test('Staged needs at least one stage, and a stage volume error is reported with its number', () {
    expect(validate(make(schedule: Staged(start: const TimeOfDayMin(6, 0), weekdays: {1}, stages: []))), hasLength(1));
    final bad = make(
      schedule: Staged(
        start: const TimeOfDayMin(6, 0),
        weekdays: {1},
        stages: [Stage(offset: Duration.zero, volume: const VolumeSpec()), Stage(offset: const Duration(minutes: 5), volume: vol(start: 0.9, target: 0.1))],
      ),
    );
    final e = validate(bad);
    expect(e, hasLength(1));
    expect(e.single, startsWith('Mốc 2:'));
  });

  test('OneShot in the past is allowed by validate (nextFire handles it)', () {
    expect(validate(make(schedule: OneShot(DateTime(2020, 1, 1)))), isEmpty);
  });
}
