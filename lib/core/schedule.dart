import 'volume_curve.dart';

/// Wall-clock time of day, independent of any date or time zone.
class TimeOfDayMin {
  final int hour;
  final int minute;
  const TimeOfDayMin(this.hour, this.minute);

  int get totalMinutes => hour * 60 + minute;

  Map<String, dynamic> toJson() => {'h': hour, 'm': minute};
  factory TimeOfDayMin.fromJson(Map<String, dynamic> j) => TimeOfDayMin(j['h'] as int, j['m'] as int);
}

/// One step of a [Staged] wake-up chain.
class Stage {
  /// Time after the chain start at which this stage begins.
  final Duration offset;
  final String? youtubeUrl;
  final VolumeSpec volume;
  const Stage({required this.offset, this.youtubeUrl, required this.volume});

  Map<String, dynamic> toJson() => {
        'offsetSeconds': offset.inSeconds,
        'youtubeUrl': youtubeUrl,
        'volume': volume.toJson(),
      };

  factory Stage.fromJson(Map<String, dynamic> j) => Stage(
        offset: Duration(seconds: j['offsetSeconds'] as int),
        youtubeUrl: j['youtubeUrl'] as String?,
        volume: VolumeSpec.fromJson(j['volume'] as Map<String, dynamic>),
      );
}

/// Weekdays use [DateTime.monday]..[DateTime.sunday] (1..7).
sealed class ScheduleSpec {
  const ScheduleSpec();

  Map<String, dynamic> toJson();

  factory ScheduleSpec.fromJson(Map<String, dynamic> j) {
    switch (j['type']) {
      case 'oneShot':
        return OneShot(DateTime.parse(j['at'] as String).toLocal());
      case 'weekly':
        return Weekly(TimeOfDayMin.fromJson(j['time'] as Map<String, dynamic>), _days(j['weekdays']));
      case 'countdown':
        return Countdown(Duration(seconds: j['durationSeconds'] as int), DateTime.parse(j['startedAt'] as String).toLocal());
      case 'windowed':
        return Windowed(
          TimeOfDayMin.fromJson(j['from'] as Map<String, dynamic>),
          TimeOfDayMin.fromJson(j['to'] as Map<String, dynamic>),
          Duration(seconds: j['everySeconds'] as int),
          _days(j['weekdays']),
        );
      case 'staged':
        return Staged(
          start: TimeOfDayMin.fromJson(j['start'] as Map<String, dynamic>),
          weekdays: _days(j['weekdays']),
          stages: [for (final s in j['stages'] as List) Stage.fromJson(s as Map<String, dynamic>)],
        );
      default:
        throw FormatException('Unknown schedule type: ${j['type']}');
    }
  }
}

Set<int> _days(Object? raw) => {for (final d in raw as List) d as int};
List<int> _sorted(Set<int> s) => (s.toList()..sort());

class OneShot extends ScheduleSpec {
  final DateTime at;
  const OneShot(this.at);

  @override
  Map<String, dynamic> toJson() => {'type': 'oneShot', 'at': at.toUtc().toIso8601String()};
}

class Weekly extends ScheduleSpec {
  final TimeOfDayMin time;
  final Set<int> weekdays;
  const Weekly(this.time, this.weekdays);

  @override
  Map<String, dynamic> toJson() => {'type': 'weekly', 'time': time.toJson(), 'weekdays': _sorted(weekdays)};
}

/// Fires once, [duration] after [startedAt] (a persisted instant, not an in-memory timer).
class Countdown extends ScheduleSpec {
  final Duration duration;
  final DateTime startedAt;
  const Countdown(this.duration, this.startedAt);

  @override
  Map<String, dynamic> toJson() =>
      {'type': 'countdown', 'durationSeconds': duration.inSeconds, 'startedAt': startedAt.toUtc().toIso8601String()};
}

/// Fires every [every] between [from] and [to] (inclusive) on the given weekdays.
class Windowed extends ScheduleSpec {
  final TimeOfDayMin from;
  final TimeOfDayMin to;
  final Duration every;
  final Set<int> weekdays;
  const Windowed(this.from, this.to, this.every, this.weekdays);

  @override
  Map<String, dynamic> toJson() => {
        'type': 'windowed',
        'from': from.toJson(),
        'to': to.toJson(),
        'everySeconds': every.inSeconds,
        'weekdays': _sorted(weekdays),
      };
}

/// A chain that starts at [start] on [weekdays]; each [Stage] begins at start + stage.offset.
class Staged extends ScheduleSpec {
  final TimeOfDayMin start;
  final Set<int> weekdays;
  final List<Stage> stages;
  const Staged({required this.start, required this.weekdays, required this.stages});

  @override
  Map<String, dynamic> toJson() => {
        'type': 'staged',
        'start': start.toJson(),
        'weekdays': _sorted(weekdays),
        'stages': [for (final s in stages) s.toJson()],
      };
}

/// The next instant (local time) after [now] at which [s] fires, or null if it never will again.
///
/// Times are rebuilt from wall-clock fields for each calendar day instead of adding 24h,
/// so a daylight-saving change cannot shift a 06:30 alarm.
DateTime? nextFire(ScheduleSpec s, DateTime now) => switch (s) {
      OneShot o => o.at.isAfter(now) ? o.at : null,
      Countdown c => _countdownFire(c, now),
      Weekly w => _earliestAfter(now, w.weekdays, (day) => [_at(day, w.time.totalMinutes)]),
      Windowed w => _windowedFire(w, now),
      Staged st => _earliestAfter(now, st.weekdays, (day) => [
            for (final stage in st.stages)
              _at(day, st.start.totalMinutes + stage.offset.inMinutes, stage.offset.inSeconds % 60),
          ]),
    };

DateTime? _countdownFire(Countdown c, DateTime now) {
  final at = c.startedAt.add(c.duration);
  return at.isAfter(now) ? at : null;
}

DateTime? _windowedFire(Windowed w, DateTime now) {
  final step = w.every.inMinutes;
  if (step < 1) return null;
  return _earliestAfter(now, w.weekdays, (day) => [
        for (var m = w.from.totalMinutes; m <= w.to.totalMinutes; m += step) _at(day, m),
      ]);
}

DateTime _at(DateTime day, int minutesFromMidnight, [int seconds = 0]) =>
    DateTime(day.year, day.month, day.day, 0, minutesFromMidnight, seconds);

/// Earliest fire time strictly after [now] among the days -1..+7 whose weekday is allowed.
/// Day -1 matters for chains that start late in the evening and run past midnight.
DateTime? _earliestAfter(DateTime now, Set<int> weekdays, List<DateTime> Function(DateTime day) firesOn) {
  DateTime? best;
  for (var d = -1; d <= 7; d++) {
    final day = DateTime(now.year, now.month, now.day + d);
    if (!weekdays.contains(day.weekday)) continue;
    for (final f in firesOn(day)) {
      if (f.isAfter(now) && (best == null || f.isBefore(best))) best = f;
    }
  }
  return best;
}
