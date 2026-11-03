import 'package:flutter_test/flutter_test.dart';
import 'package:video_timer_player/core/schedule.dart';
import 'package:video_timer_player/core/volume_curve.dart';
import 'package:video_timer_player/ui/alarm_summary.dart';

void main() {
  test('durationLabel', () {
    expect(durationLabel(const Duration(seconds: 30)), '30 giây');
    expect(durationLabel(const Duration(seconds: 90)), '1 phút 30 giây');
    expect(durationLabel(const Duration(minutes: 30)), '30 phút');
    expect(durationLabel(const Duration(minutes: 65)), '1 giờ 5 phút');
    expect(durationLabel(Duration.zero), '0 giây');
  });

  test('untilLabel', () {
    final now = DateTime(2026, 11, 3, 6, 0);
    expect(untilLabel(now.add(const Duration(seconds: 20)), now), 'sắp kêu');
    expect(untilLabel(now.add(const Duration(minutes: 12)), now), 'sau 12 phút');
    expect(untilLabel(now.add(const Duration(hours: 7, minutes: 12)), now), 'sau 7 giờ 12 phút');
    expect(untilLabel(now.add(const Duration(days: 2, hours: 3)), now), 'sau 2 ngày 3 giờ');
  });

  test('repeatLabel', () {
    expect(repeatLabel({1, 2, 3, 4, 5, 6, 7}), 'Mỗi ngày');
    expect(repeatLabel({1, 2, 3, 4, 5}), 'Thứ 2 – Thứ 6');
    expect(repeatLabel({6, 7}), 'Cuối tuần');
    expect(repeatLabel({1, 3}), 'T2, T4');
    expect(repeatLabel({}), 'Không lặp');
  });

  test('volumeLabel and holdLabel', () {
    const v = VolumeSpec(start: 0, target: 0.7, ramp: Duration(seconds: 60), curve: RampCurve.easeIn, hold: Duration(minutes: 30));
    expect(volumeLabel(v), 'Âm lượng 0% → 70% trong 1 phút (êm đầu)');
    expect(holdLabel(v), 'Phát tối đa 30 phút');
    expect(volumeLabel(const VolumeSpec(target: 0.5, ramp: Duration.zero)), 'Âm lượng 50% ngay từ đầu');
  });

  test('scheduleHeadline and scheduleKind', () {
    const w = Weekly(TimeOfDayMin(6, 5), {1, 2, 3, 4, 5});
    expect(scheduleHeadline(w), '06:05');
    expect(scheduleKind(w), 'Lặp hằng tuần: Thứ 2 – Thứ 6');
    expect(scheduleDays(w), {1, 2, 3, 4, 5});
    expect(scheduleHeadline(const Windowed(TimeOfDayMin(6, 0), TimeOfDayMin(7, 30), Duration(minutes: 10), {1})), '06:00 – 07:30');
    expect(scheduleDays(Countdown(const Duration(minutes: 20), DateTime(2026))), isNull);
  });
}
