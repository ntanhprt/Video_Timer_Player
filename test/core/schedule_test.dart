import 'package:flutter_test/flutter_test.dart';
import 'package:video_timer_player/core/schedule.dart';
import 'package:video_timer_player/core/volume_curve.dart';

const allDays = {1, 2, 3, 4, 5, 6, 7};

void main() {
  group('OneShot / Countdown', () {
    test('OneShot in the future returns itself, in the past returns null', () {
      final at = DateTime(2026, 11, 3, 6, 30);
      expect(nextFire(OneShot(at), DateTime(2026, 11, 3, 6, 0)), at);
      expect(nextFire(OneShot(at), DateTime(2026, 11, 3, 6, 30)), isNull);
      expect(nextFire(OneShot(at), DateTime(2026, 11, 4)), isNull);
    });

    test('Countdown fires startedAt + duration, then never again', () {
      final c = Countdown(const Duration(minutes: 15), DateTime(2026, 11, 3, 10, 0));
      expect(nextFire(c, DateTime(2026, 11, 3, 10, 5)), DateTime(2026, 11, 3, 10, 15));
      expect(nextFire(c, DateTime(2026, 11, 3, 10, 15)), isNull);
    });
  });

  group('Weekly', () {
    final mondayWed = Weekly(const TimeOfDayMin(6, 30), {DateTime.monday, DateTime.wednesday});

    test('Tuesday 07:00 -> Wednesday 06:30', () {
      final tue = DateTime(2026, 11, 3, 7, 0);
      expect(tue.weekday, DateTime.tuesday);
      expect(nextFire(mondayWed, tue), DateTime(2026, 11, 4, 6, 30));
    });

    test('exactly at fire time returns the next occurrence, not itself', () {
      final wed = DateTime(2026, 11, 4, 6, 30);
      expect(nextFire(mondayWed, wed), DateTime(2026, 11, 9, 6, 30));
    });

    test('later the same day is returned when still ahead', () {
      expect(nextFire(mondayWed, DateTime(2026, 11, 4, 5, 0)), DateTime(2026, 11, 4, 6, 30));
    });

    test('keeps 06:30 local across a daylight-saving change', () {
      final daily = Weekly(const TimeOfDayMin(6, 30), allDays);
      for (var d = DateTime(2026, 10, 28, 12); d.isBefore(DateTime(2026, 11, 6)); d = DateTime(d.year, d.month, d.day + 1, 12)) {
        final f = nextFire(daily, d)!;
        expect([f.hour, f.minute], [6, 30], reason: 'from $d got $f');
        expect(f.isAfter(d), isTrue);
      }
    });
  });

  group('Windowed', () {
    final w = Windowed(const TimeOfDayMin(6, 0), const TimeOfDayMin(7, 0), const Duration(minutes: 10), allDays);

    test('returns next slot inside the window', () {
      expect(nextFire(w, DateTime(2026, 11, 3, 6, 25)), DateTime(2026, 11, 3, 6, 30));
    });

    test('window end is inclusive, then rolls to next day start', () {
      expect(nextFire(w, DateTime(2026, 11, 3, 6, 50)), DateTime(2026, 11, 3, 7, 0));
      expect(nextFire(w, DateTime(2026, 11, 3, 7, 0)), DateTime(2026, 11, 4, 6, 0));
    });

    test('non-positive interval never fires', () {
      final bad = Windowed(const TimeOfDayMin(6, 0), const TimeOfDayMin(7, 0), Duration.zero, allDays);
      expect(nextFire(bad, DateTime(2026, 11, 3)), isNull);
    });
  });

  group('Staged', () {
    Stage st(int min) => Stage(offset: Duration(minutes: min), volume: const VolumeSpec());
    final s = Staged(
      start: const TimeOfDayMin(6, 0),
      weekdays: {1, 2, 3, 4, 5},
      stages: [st(0), st(20), st(30)],
    );

    test('picks the first stage not yet passed', () {
      expect(nextFire(s, DateTime(2026, 11, 3, 6, 10)), DateTime(2026, 11, 3, 6, 20));
      expect(nextFire(s, DateTime(2026, 11, 3, 6, 25)), DateTime(2026, 11, 3, 6, 30));
    });

    test('after the last stage, rolls to the next allowed day', () {
      final tue = DateTime(2026, 11, 3, 6, 35);
      expect(nextFire(s, tue), DateTime(2026, 11, 4, 6, 0));
      final fri = DateTime(2026, 11, 6, 6, 35);
      expect(fri.weekday, DateTime.friday);
      expect(nextFire(s, fri), DateTime(2026, 11, 9, 6, 0));
    });

    test('a chain crossing midnight is still found after midnight', () {
      final late = Staged(
        start: const TimeOfDayMin(23, 50),
        weekdays: allDays,
        stages: [st(0), st(20)],
      );
      expect(nextFire(late, DateTime(2026, 11, 4, 0, 5)), DateTime(2026, 11, 4, 0, 10));
    });
  });
}
