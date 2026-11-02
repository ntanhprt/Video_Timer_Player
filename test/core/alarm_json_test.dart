import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_timer_player/core/alarm.dart';
import 'package:video_timer_player/core/schedule.dart';
import 'package:video_timer_player/core/volume_curve.dart';

Alarm withSchedule(ScheduleSpec s) => Alarm(
      id: 'id-1',
      name: 'Báo thức',
      schedule: s,
      youtubeUrls: ['https://youtu.be/dQw4w9WgXcQ', 'https://youtu.be/abcdefghijk'],
      volume: const VolumeSpec(start: 0.1, target: 0.9, ramp: Duration(seconds: 90), curve: RampCurve.easeOut, hold: Duration(minutes: 45)),
      output: OutputKind.bluetooth,
      fallbackPath: '/sdcard/fallback.mp3',
      enabled: false,
      rev: 7,
      updatedAt: DateTime.utc(2026, 11, 2, 9, 30),
      deleted: true,
    );

void main() {
  final schedules = <ScheduleSpec>[
    OneShot(DateTime(2026, 11, 3, 6, 30)),
    Weekly(const TimeOfDayMin(6, 30), {1, 3, 5}),
    Countdown(const Duration(minutes: 15), DateTime(2026, 11, 3, 10)),
    Windowed(const TimeOfDayMin(6, 0), const TimeOfDayMin(7, 0), const Duration(minutes: 10), {1, 2}),
    Staged(
      start: const TimeOfDayMin(6, 0),
      weekdays: {1, 2, 3},
      stages: [
        const Stage(offset: Duration.zero, volume: VolumeSpec()),
        Stage(offset: const Duration(minutes: 20), youtubeUrl: 'https://youtu.be/abcdefghijk', volume: const VolumeSpec(target: 1.0)),
      ],
    ),
  ];

  for (final s in schedules) {
    test('${s.runtimeType} survives a JSON round trip (through text)', () {
      final a = withSchedule(s);
      final back = Alarm.fromJson(jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>);
      expect(back.toJson(), a.toJson());
      expect(back.schedule.runtimeType, s.runtimeType);
      expect(back.deleted, isTrue);
      expect(back.rev, 7);
    });
  }

  test('unknown schedule type is rejected, not silently ignored', () {
    final j = withSchedule(schedules[1]).toJson();
    (j['schedule'] as Map<String, dynamic>)['type'] = 'lunar';
    expect(() => Alarm.fromJson(j), throwsFormatException);
  });

  test('toJson uses the field names the web API relies on', () {
    final j = withSchedule(schedules[1]).toJson();
    expect(j.keys, containsAll(['id', 'name', 'schedule', 'youtubeUrls', 'volume', 'output', 'fallbackPath', 'enabled', 'rev', 'updatedAt', 'deleted']));
  });
}
