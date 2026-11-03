import '../voice_command.dart';

/// What a command may do. Built by the ring controller for the alarm that is ringing (or, on the
/// microphone test screen, for no alarm at all).
class CommandContext {
  /// Stops the ringing alarm.
  final Future<void> Function() stop;

  /// Stops it and rings it again after the delay.
  final Future<void> Function(Duration delay) snooze;

  /// Shows a message on the screen.
  final void Function(String message) say;

  final DateTime Function() now;

  /// One line per known command, for the "help" command.
  final List<String> Function() describeCommands;

  const CommandContext({
    required this.stop,
    required this.snooze,
    required this.say,
    required this.now,
    required this.describeCommands,
  });
}

typedef Args = Map<String, Object?>;

/// One thing the user can say, and what it does. To add a command, build one of these and
/// register it in the [CommandRegistry]; nothing else needs to change.
class VoiceIntent {
  /// Stable name, e.g. "stop".
  final String id;

  /// Short Vietnamese description shown in the help list.
  final String title;

  /// Example sentences shown to the user.
  final List<String> examples;

  /// Phrases that trigger the command; matched anywhere in the sentence, ignoring diacritics and
  /// tolerating one wrong letter in longer words (speech engines slip).
  final List<List<String>> patterns;

  /// Extra condition for commands that are not a fixed phrase ("mười phút nữa").
  final bool Function(List<String> tokens)? when;

  /// Pulls values out of the sentence (the time to snooze, ...), handed to [run] as `args`.
  final Args Function(List<String> tokens)? slots;

  /// Does the command. The returned text, if any, is shown on screen.
  final Future<String?> Function(CommandContext ctx, Args args) run;

  /// True when the command ends the ringing (stop, snooze): listening then stops.
  final bool endsRing;

  /// Wins over lower priorities when one sentence matches several commands.
  final int priority;

  VoiceIntent({
    required this.id,
    required this.title,
    this.examples = const [],
    List<String> patterns = const [],
    this.when,
    this.slots,
    required this.run,
    this.endsRing = false,
    this.priority = 0,
  }) : patterns = [for (final p in patterns) tokenizeVietnamese(p)];
}

class IntentMatch {
  final VoiceIntent intent;
  final double score;
  final Args args;
  const IntentMatch(this.intent, this.score, this.args);

  @override
  String toString() => '${intent.id} (${score.toStringAsFixed(2)}) $args';
}

/// Edit distance (insert, delete, replace) between two short words.
int editDistance(String a, String b) {
  if (a == b) return 0;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      cur[j] = [cur[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost].reduce((x, y) => x < y ? x : y);
    }
    prev = cur;
  }
  return prev[b.length];
}

/// Same word, or (for words of 4+ letters) one letter off.
bool wordsMatch(String a, String b) => a == b || (a.length >= 4 && b.length >= 4 && editDistance(a, b) <= 1);

/// 1.0 when [pattern] appears in [tokens] word for word, 0.9 when it needed a one-letter slip
/// forgiven, null when it does not appear.
double? matchPattern(List<String> pattern, List<String> tokens) {
  if (pattern.isEmpty || pattern.length > tokens.length) return null;
  double? best;
  for (var start = 0; start + pattern.length <= tokens.length; start++) {
    var exact = true;
    var ok = true;
    for (var k = 0; k < pattern.length && ok; k++) {
      final t = tokens[start + k];
      if (t != pattern[k]) {
        exact = false;
        ok = wordsMatch(pattern[k], t);
      }
    }
    if (ok) {
      final score = exact ? 1.0 : 0.9;
      if (best == null || score > best) best = score;
    }
  }
  return best;
}
