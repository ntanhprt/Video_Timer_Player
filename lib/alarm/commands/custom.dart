import 'dart:convert';
import 'dart:io';

import '../voice_command.dart';
import 'intent.dart';

/// A command the user taught: say [phrase] and the app does [action].
class CustomCommand {
  final String phrase;

  /// "stop" or "snooze".
  final String action;
  final int minutes;
  const CustomCommand({required this.phrase, required this.action, this.minutes = 10});

  Map<String, Object?> toJson() => {'phrase': phrase, 'action': action, 'minutes': minutes};

  factory CustomCommand.fromJson(Map<String, dynamic> j) =>
      CustomCommand(phrase: j['phrase'] as String, action: j['action'] as String, minutes: (j['minutes'] as int?) ?? 10);

  String get label => action == 'stop' ? 'Tắt chuông' : 'Báo lại $minutes phút';

  @override
  bool operator ==(Object other) => other is CustomCommand && other.phrase == phrase && other.action == action && other.minutes == minutes;

  @override
  int get hashCode => Object.hash(phrase, action, minutes);
}

/// How well the words [heard] contain the taught [phrase]: the share of the phrase's words found
/// (allowing one slip per longer word). The sentence may be a little longer than the phrase.
double phraseCoverage(List<String> phrase, List<String> heard) {
  if (phrase.isEmpty || heard.length > phrase.length + 4) return 0;
  final found = phrase.where((w) => heard.any((h) => wordsMatch(w, h))).length;
  return found / phrase.length;
}

/// The command a [CustomCommand] stands for; it outranks the built-in ones.
VoiceIntent customIntent(int index, CustomCommand c) {
  final words = tokenizeVietnamese(c.phrase);
  return VoiceIntent(
    id: '$customPrefix$index',
    title: '',
    when: (tokens) => phraseCoverage(words, tokens) >= 0.8,
    priority: 10,
    endsRing: true,
    run: (ctx, args) async {
      if (c.action == 'stop') {
        await ctx.stop();
        return 'Đã tắt chuông ("${c.phrase}")';
      }
      final d = clampSnooze(Duration(minutes: c.minutes));
      await ctx.snooze(d);
      return 'Báo lại sau ${d.inMinutes} phút ("${c.phrase}")';
    },
  );
}

const customPrefix = 'custom:';

/// The user's own commands, kept in a JSON file.
class CustomCommandStore {
  final File file;
  CustomCommandStore(this.file);

  Future<List<CustomCommand>> load() async {
    try {
      if (!await file.exists()) return [];
      final list = jsonDecode(await file.readAsString()) as List;
      return [for (final e in list) CustomCommand.fromJson(e as Map<String, dynamic>)];
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<CustomCommand> commands) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode([for (final c in commands) c.toJson()]));
  }
}
