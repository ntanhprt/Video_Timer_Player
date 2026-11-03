import '../core/schedule.dart';
import '../core/volume_curve.dart';

String two(int n) => n.toString().padLeft(2, '0');

String timeLabel(TimeOfDayMin t) => '${two(t.hour)}:${two(t.minute)}';

/// "30 giây", "1 phút", "1 phút 30 giây", "1 giờ 5 phút".
String durationLabel(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  final parts = [if (h > 0) '$h giờ', if (m > 0) '$m phút', if (s > 0 && h == 0) '$s giây'];
  return parts.isEmpty ? '0 giây' : parts.join(' ');
}

/// "sau 7 giờ 12 phút", "sau 2 ngày 3 giờ", "sau 5 phút", "ngay bây giờ".
String untilLabel(DateTime next, DateTime now) {
  final d = next.difference(now);
  if (d.inSeconds < 60) return 'sắp kêu';
  if (d.inDays >= 1) {
    final h = d.inHours % 24;
    return 'sau ${d.inDays} ngày${h > 0 ? ' $h giờ' : ''}';
  }
  if (d.inHours >= 1) return 'sau ${d.inHours} giờ ${d.inMinutes % 60} phút';
  return 'sau ${d.inMinutes} phút';
}

const weekdayShort = {1: 'T2', 2: 'T3', 3: 'T4', 4: 'T5', 5: 'T6', 6: 'T7', 7: 'CN'};

/// "Mỗi ngày", "Thứ 2 – Thứ 6", "Cuối tuần" or the listed days.
String repeatLabel(Set<int> days) {
  if (days.length == 7) return 'Mỗi ngày';
  if (days.isEmpty) return 'Không lặp';
  final sorted = days.toList()..sort();
  if (sorted.length == 5 && sorted.first == 1 && sorted.last == 5) return 'Thứ 2 – Thứ 6';
  if (sorted.length == 2 && sorted[0] == 6 && sorted[1] == 7) return 'Cuối tuần';
  return sorted.map((d) => weekdayShort[d]).join(', ');
}

String curveLabel(RampCurve c) => switch (c) {
      RampCurve.linear => 'đều',
      RampCurve.easeIn => 'êm đầu',
      RampCurve.easeOut => 'nhanh đầu',
    };

String pct(double v) => '${(v * 100).round()}%';

/// "Âm lượng 0% → 70% trong 1 phút (êm đầu)"; no ramp reads "Âm lượng 70% ngay".
String volumeLabel(VolumeSpec v) => v.ramp <= Duration.zero
    ? 'Âm lượng ${pct(v.target)} ngay từ đầu'
    : 'Âm lượng ${pct(v.start)} → ${pct(v.target)} trong ${durationLabel(v.ramp)} (${curveLabel(v.curve)})';

String holdLabel(VolumeSpec v) => 'Phát tối đa ${durationLabel(v.hold)}';

/// The big headline of an alarm card: the time for time-of-day schedules, otherwise a short phrase.
String scheduleHeadline(ScheduleSpec s) => switch (s) {
      Weekly(:final time) => timeLabel(time),
      Staged(:final start) => timeLabel(start),
      Windowed(:final from, :final to) => '${timeLabel(from)} – ${timeLabel(to)}',
      OneShot(:final at) => '${two(at.hour)}:${two(at.minute)}',
      Countdown(:final duration) => 'Hẹn ${durationLabel(duration)}',
    };

/// Which days the schedule repeats on, or null when it does not repeat by weekday.
Set<int>? scheduleDays(ScheduleSpec s) => switch (s) {
      Weekly(:final weekdays) => weekdays,
      Staged(:final weekdays) => weekdays,
      Windowed(:final weekdays) => weekdays,
      _ => null,
    };

/// One line saying what kind of schedule this is, e.g. "Hằng tuần: Thứ 2 – Thứ 6".
String scheduleKind(ScheduleSpec s) => switch (s) {
      Weekly(:final weekdays) => 'Lặp hằng tuần: ${repeatLabel(weekdays)}',
      Staged(:final weekdays, :final stages) => 'Đánh thức ${stages.length} mốc: ${repeatLabel(weekdays)}',
      Windowed(:final every, :final weekdays) => 'Lặp mỗi ${durationLabel(every)}: ${repeatLabel(weekdays)}',
      OneShot(:final at) => 'Một lần, ngày ${two(at.day)}/${two(at.month)}/${at.year}',
      Countdown() => 'Hẹn giờ đếm ngược, kêu một lần',
    };
