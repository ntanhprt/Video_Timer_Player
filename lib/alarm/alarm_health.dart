/// What can stop the alarm from ringing, found by looking at the phone rather than at our own state.
enum AlarmProblem {
  /// Alarms we should have registered with Android are gone: the app was force-stopped (MIUI
  /// "clean up", swiping it away, battery saver) and Android drops every alarm of a stopped app.
  wiped,
  notifications,
  exactAlarm,
  battery,
}

class AlarmHealth {
  final Set<AlarmProblem> problems;
  const AlarmHealth([this.problems = const {}]);

  static const ok = AlarmHealth();

  bool get isOk => problems.isEmpty;
  bool get wiped => problems.contains(AlarmProblem.wiped);

  AlarmHealth without(AlarmProblem p) => AlarmHealth({...problems}..remove(p));

  @override
  bool operator ==(Object other) => other is AlarmHealth && other.problems.length == problems.length && other.problems.containsAll(problems);

  @override
  int get hashCode => Object.hashAllUnordered(problems);
}

/// True when alarms are due but Android knows none of them.
///
/// A normal ring only consumes one registration (the other upcoming ones stay), so "none of ours
/// registered" can only come from the system dropping them all.
bool alarmsWereWiped({required Set<int> expected, required Set<int> registered}) =>
    expected.isNotEmpty && expected.intersection(registered).isEmpty;

/// Combines a fresh look at the phone with what was already reported: a wipe stays flagged until
/// the user has seen it, even though re-registering already fixed it.
AlarmHealth assessHealth({
  required Set<int> expected,
  required Set<int> registered,
  required Set<AlarmProblem> permissionProblems,
  required AlarmHealth previous,
}) =>
    AlarmHealth({
      ...permissionProblems,
      if (previous.wiped || alarmsWereWiped(expected: expected, registered: registered)) AlarmProblem.wiped,
    });
