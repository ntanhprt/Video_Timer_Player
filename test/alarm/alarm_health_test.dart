import 'package:flutter_test/flutter_test.dart';
import 'package:video_timer_player/alarm/alarm_health.dart';

void main() {
  group('alarmsWereWiped', () {
    test('nothing due, nothing to lose', () {
      expect(alarmsWereWiped(expected: {}, registered: {}), isFalse);
      expect(alarmsWereWiped(expected: {}, registered: {5}), isFalse);
    });

    test('due alarms that Android knows none of = wiped', () {
      expect(alarmsWereWiped(expected: {10, 11, 12}, registered: {}), isTrue);
      // Only the test/snooze alarms survived: still wiped.
      expect(alarmsWereWiped(expected: {10, 11, 12}, registered: {1, 2}), isTrue);
    });

    test('a normal ring consumes one registration, the rest stay: not wiped', () {
      expect(alarmsWereWiped(expected: {10, 11, 12}, registered: {11, 12}), isFalse);
    });
  });

  group('assessHealth', () {
    AlarmHealth run({Set<int> expected = const {10}, Set<int> registered = const {10}, Set<AlarmProblem> perms = const {}, AlarmHealth previous = AlarmHealth.ok}) =>
        assessHealth(expected: expected, registered: registered, permissionProblems: perms, previous: previous);

    test('healthy phone', () => expect(run().isOk, isTrue));

    test('flags a wipe', () => expect(run(registered: {}).problems, {AlarmProblem.wiped}));

    test('a wipe stays flagged on the next check, after we re-registered', () {
      final first = run(registered: {});
      expect(run(previous: first).wiped, isTrue);
    });

    test('dismissing clears it for good', () {
      final first = run(registered: {});
      final after = run(previous: first.without(AlarmProblem.wiped));
      expect(after.isOk, isTrue);
    });

    test('permission problems come and go with the permissions', () {
      final bad = run(perms: {AlarmProblem.battery});
      expect(bad.problems, {AlarmProblem.battery});
      expect(run(previous: bad).isOk, isTrue);
    });

    test('equality is by content', () {
      expect(const AlarmHealth({AlarmProblem.battery}), const AlarmHealth({AlarmProblem.battery}));
      expect(const AlarmHealth({AlarmProblem.battery}) == AlarmHealth.ok, isFalse);
    });
  });
}
