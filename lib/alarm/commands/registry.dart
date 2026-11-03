import 'intent.dart';

/// All the commands the app understands, and how a sentence is matched to one of them.
class CommandRegistry {
  /// Below this a sentence is not taken as a command.
  static const threshold = 0.75;

  final _intents = <String, VoiceIntent>{};

  List<VoiceIntent> get intents => List.unmodifiable(_intents.values);

  /// Adds (or replaces, by id) a command.
  void register(VoiceIntent intent) => _intents[intent.id] = intent;

  void registerAll(Iterable<VoiceIntent> intents) => intents.forEach(register);

  void unregister(String id) => _intents.remove(id);

  /// Removes every command whose id starts with [prefix] (used to reload the user's own commands).
  void unregisterPrefix(String prefix) => _intents.removeWhere((id, _) => id.startsWith(prefix));

  /// The best command for [tokens] (see `tokenizeVietnamese`), or null. Higher priority wins, then
  /// the better match.
  IntentMatch? match(List<String> tokens) {
    if (tokens.isEmpty) return null;
    IntentMatch? best;
    for (final i in _intents.values) {
      double? score;
      for (final p in i.patterns) {
        final s = matchPattern(p, tokens);
        if (s != null && (score == null || s > score)) score = s;
      }
      final w = i.when;
      if (w != null && w(tokens)) score = score == null || score < 0.9 ? 0.9 : score;
      if (score == null || score < threshold) continue;
      final m = IntentMatch(i, score, i.slots?.call(tokens) ?? const {});
      if (best == null ||
          i.priority > best.intent.priority ||
          (i.priority == best.intent.priority && score > best.score)) {
        best = m;
      }
    }
    return best;
  }

  /// "title — e.g. "example"" for each command, for the help screen.
  List<String> describe() => [
        for (final i in _intents.values)
          if (i.title.isNotEmpty) '${i.title}${i.examples.isEmpty ? '' : ' — nói: "${i.examples.first}"'}',
      ];
}
