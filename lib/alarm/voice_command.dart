import 'dart:convert';

/// What the user said to a ringing alarm.
sealed class VoiceCommand {
  const VoiceCommand();
}

class StopCommand extends VoiceCommand {
  const StopCommand();
  @override
  bool operator ==(Object other) => other is StopCommand;
  @override
  int get hashCode => 1;
  @override
  String toString() => 'tắt';
}

class SnoozeCommand extends VoiceCommand {
  final Duration delay;
  const SnoozeCommand(this.delay);
  @override
  bool operator ==(Object other) => other is SnoozeCommand && other.delay == delay;
  @override
  int get hashCode => delay.hashCode;
  @override
  String toString() => 'báo lại sau ${delay.inMinutes} phút';
}

/// Longest snooze a voice command may ask for.
const maxVoiceSnooze = Duration(hours: 3);

/// Snooze used when the user says "báo lại" without a time.
const defaultVoiceSnooze = Duration(minutes: 5);

const _from = 'àáảãạăằắẳẵặâầấẩẫậèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵđ';
const _to = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';

/// Lower-case, without Vietnamese diacritics: speech engines vary the tones they write.
String foldVietnamese(String s) {
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    final c = String.fromCharCode(r);
    final i = _from.indexOf(c);
    b.write(i >= 0 ? _to[i] : c);
  }
  return b.toString();
}

const _units = {
  'mot': 1, 'hai': 2, 'ba': 3, 'bon': 4, 'tu': 4, 'nam': 5, 'lam': 5, 'bay': 7, 'tam': 8, 'chin': 9,
};

/// "sáu" is also the word for "after", so it only counts as six before a time unit.
const _sixUnits = {'phut', 'gio', 'tieng'};

/// Reads the first number in [tokens] (digits or Vietnamese words) and returns it with the
/// index just after it, or null.
({int value, int next})? _readNumber(List<String> tokens) {
  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    final digits = int.tryParse(t);
    if (digits != null) return (value: digits, next: i + 1);
    if (t == 'muoi') {
      var v = 10;
      var next = i + 1;
      if (next < tokens.length && _units.containsKey(tokens[next])) {
        v += _units[tokens[next]]!;
        next++;
      }
      return (value: v, next: next);
    }
    final isSix = t == 'sau' && i + 1 < tokens.length && _sixUnits.contains(tokens[i + 1]);
    final u = isSix ? 6 : _units[t];
    if (u == null) continue;
    if (i + 1 < tokens.length && (tokens[i + 1] == 'muoi' || tokens[i + 1] == 'chuc')) {
      var v = u * 10;
      var next = i + 2;
      if (next < tokens.length && _units.containsKey(tokens[next])) {
        v += _units[tokens[next]]!;
        next++;
      }
      return (value: v, next: next);
    }
    return (value: u, next: i + 1);
  }
  return null;
}

bool _hasPhrase(String folded, List<String> phrases) => phrases.any((p) => RegExp('\\b$p\\b').hasMatch(folded));

/// Turns recognised speech into a command, or null when it is not one.
///
/// "tắt chuông đi" → stop; "mười phút nữa báo lại" / "báo lại sau 1 tiếng" → snooze.
/// Snoozing wins when a sentence has both ("tắt đi, 10 phút nữa báo lại").
VoiceCommand? parseVoiceCommand(String text) {
  final folded = foldVietnamese(text).replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (folded.isEmpty) return null;

  const snoozeWords = ['bao lai', 'nhac lai', 'ngu them', 'hoan lai', 'bao thuc lai', 'keu lai'];
  if (_hasPhrase(folded, snoozeWords)) {
    final tokens = folded.split(' ');
    final n = _readNumber(tokens);
    Duration d;
    if (n != null) {
      var minutes = n.value;
      final unit = n.next < tokens.length ? tokens[n.next] : '';
      if (unit == 'gio' || unit == 'tieng') {
        minutes *= 60;
        if (n.next + 1 < tokens.length && tokens[n.next + 1] == 'ruoi') minutes += 30;
      }
      d = Duration(minutes: minutes);
    } else if (RegExp(r'\bnua (gio|tieng)\b').hasMatch(folded)) {
      d = const Duration(minutes: 30);
    } else {
      d = defaultVoiceSnooze;
    }
    if (d < const Duration(minutes: 1)) d = defaultVoiceSnooze;
    if (d > maxVoiceSnooze) d = maxVoiceSnooze;
    return SnoozeCommand(d);
  }

  const stopPhrases = [
    'tat chuong', 'tat bao thuc', 'tat nhac', 'tat di', 'tat het', 'tat may', 'tat loa', 'tat dong ho',
    'dung lai', 'dung chuong', 'dung nhac', 'im di', 'im lang', 'thoi di', 'het chuong',
  ];
  if (_hasPhrase(folded, stopPhrases)) return const StopCommand();
  return null;
}

const _words = ['', 'một', 'hai', 'ba', 'bốn', 'năm', 'sáu', 'bảy', 'tám', 'chín'];

/// 1..59 in spoken Vietnamese: 5 → "năm", 15 → "mười lăm", 25 → "hai mươi lăm".
String viNumber(int n) {
  assert(n >= 1 && n < 60);
  if (n < 10) return _words[n];
  final tens = n ~/ 10, u = n % 10;
  final tail = u == 0 ? '' : u == 5 ? 'lăm' : (u == 1 && tens > 1) ? 'mốt' : _words[u];
  final head = tens == 1 ? 'mười' : '${_words[tens]} mươi';
  return tail.isEmpty ? head : '$head $tail';
}

/// Minutes offered as spoken snooze times.
const voiceSnoozeMinutes = [1, 2, 3, 5, 10, 15, 20, 25, 30, 40, 45, 50, 55];

const _stopPhrasesSpoken = ['tắt chuông đi', 'tắt báo thức', 'tắt nhạc đi', 'tắt đi', 'dừng lại', 'im đi', 'thôi đi'];

/// Every sentence the recogniser may produce. Limiting it to these makes recognition far more
/// reliable than free dictation, especially with music playing.
List<String> voicePhrases() => [
      ..._stopPhrasesSpoken,
      'báo lại',
      for (final m in voiceSnoozeMinutes) ...['${viNumber(m)} phút nữa báo lại', 'báo lại sau ${viNumber(m)} phút'],
      'một tiếng nữa báo lại',
      'hai tiếng nữa báo lại',
      'một tiếng rưỡi nữa báo lại',
      'nửa tiếng nữa báo lại',
    ];

/// JSON grammar for the recogniser: the phrases plus "[unk]" for everything else.
String voiceGrammar() => jsonEncode([...voicePhrases(), '[unk]']);
