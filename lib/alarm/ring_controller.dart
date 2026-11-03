import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:flutter/foundation.dart';

import 'commands/builtin.dart';
import 'commands/custom.dart';
import 'commands/intent.dart';
import 'commands/registry.dart';
import 'plan.dart';
import 'tuya_alarms.dart';
import 'voice_bridge.dart';
import 'voice_command.dart';

/// Looks after an alarm while it rings: stops it when its play time is over, and listens for
/// spoken commands ("tắt chuông đi", "mười phút nữa báo lại") with an offline recogniser.
class RingController {
  /// Called to snooze the given ringing alarm.
  final Future<void> Function(AlarmSettings alarm, Duration delay) onSnooze;

  /// Runs a Tuya timer: switch the device with that app id on or off.
  final Future<void> Function(String deviceId, bool on)? onTuya;
  final _tuyaHandled = <int>{};
  final DateTime Function() _now;

  /// What the ringing screen shows about the microphone.
  final voiceStatus = ValueNotifier<String>('');

  /// Microphone loudness 0..1, so the user can see that they are being heard.
  final voiceLevel = ValueNotifier<double>(0);

  final _stopTimers = <int, Timer>{};
  late final VoiceBridge _voice = VoiceBridge(_onVoiceEvent);
  VoiceBridge get bridge => _voice;
  bool _testing = false;
  StreamSubscription<AlarmSet>? _sub;
  Set<AlarmSettings> _ringing = {};
  bool _acted = false;
  String _device = '';
  String _partial = '';
  final _heard = <String>[];

  /// Every command the app understands (built-in plus the ones the user taught).
  final registry = CommandRegistry()..registerAll(builtinIntents());

  /// Where the user's own commands are kept; null disables teaching.
  final CustomCommandStore? store;

  /// The user's own commands.
  final customCommands = ValueNotifier<List<CustomCommand>>([]);

  /// Sentences heard but not understood: the user can teach one of them as a command.
  final unrecognized = ValueNotifier<List<String>>([]);

  RingController({required this.onSnooze, this.onTuya, this.store, DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  void start() {
    unawaited(_loadCustom());
    _sub = Alarm.ringing.listen((s) => _onRinging(s.alarms));
    _onRinging(Alarm.ringing.value.alarms);
    // Load the speech model now rather than at the moment the alarm rings.
    unawaited(_voice.prepare().catchError((Object e) => debugPrint('Voice prepare failed: $e')));
  }

  Future<void> _loadCustom() async {
    customCommands.value = await store?.load() ?? [];
    _registerCustom();
  }

  void _registerCustom() {
    registry.unregisterPrefix(customPrefix);
    final list = customCommands.value;
    for (var i = 0; i < list.length; i++) {
      registry.register(customIntent(i, list[i]));
    }
  }

  /// Teaches the app: from now on saying [phrase] does [action] ("stop" or "snooze").
  Future<void> teach(String phrase, String action, {int minutes = 10}) async {
    final c = CustomCommand(phrase: phrase.trim(), action: action, minutes: minutes);
    if (c.phrase.isEmpty) return;
    customCommands.value = [...customCommands.value.where((e) => e.phrase != c.phrase), c];
    unrecognized.value = [...unrecognized.value]..remove(phrase);
    _registerCustom();
    await store?.save(customCommands.value);
  }

  Future<void> forget(CustomCommand c) async {
    customCommands.value = [...customCommands.value]..remove(c);
    _registerCustom();
    await store?.save(customCommands.value);
  }

  void dispose() {
    _sub?.cancel();
    for (final t in _stopTimers.values) {
      t.cancel();
    }
  }

  void _onRinging(Set<AlarmSettings> all) {
    // Helper alarms that only exist to wake the app for a Tuya timer: do the job, silence them,
    // and keep them away from the alarm logic below.
    final ringing = <AlarmSettings>{};
    for (final a in all) {
      final t = tuyaFromPayload(a.payload);
      if (t == null) {
        ringing.add(a);
      } else if (_tuyaHandled.add(a.id)) {
        unawaited(() async {
          try {
            await onTuya?.call(t.device, t.on);
          } finally {
            await Alarm.stop(a.id);
          }
        }());
      }
    }
    _tuyaHandled.removeWhere((id) => !all.any((a) => a.id == id));
    final wasEmpty = _ringing.isEmpty;
    _ringing = ringing;
    final ids = ringing.map((a) => a.id).toSet();
    for (final id in _stopTimers.keys.where((id) => !ids.contains(id)).toList()) {
      _stopTimers.remove(id)?.cancel();
    }
    for (final a in ringing) {
      final hold = holdFromPayload(a.payload);
      if (hold == null) continue;
      _stopTimers.putIfAbsent(a.id, () {
        final left = a.dateTime.add(hold).difference(_now());
        return Timer(left.isNegative ? Duration.zero : left, () async {
          debugPrint('Ring: play time over, stopping ${a.id}');
          await Alarm.stop(a.id);
        });
      });
    }
    if (ringing.isEmpty) {
      _acted = false;
      voiceStatus.value = '';
      voiceLevel.value = 0;
      _heard.clear();
      _partial = '';
      unawaited(_voice.stop().catchError((Object _) {}));
    } else if (wasEmpty) {
      _acted = false;
      voiceStatus.value = 'Đang bật micro...';
      unawaited(_voice.start().catchError((Object e) {
        voiceStatus.value = 'Không bật được giọng nói: $e';
      }));
    }
  }

  /// Shows what the recogniser hears: the last few finished sentences and the one in progress.
  void _show(String header) {
    final lines = [header, if (_device.isNotEmpty) 'Micro: $_device', ..._heard, if (_partial.isNotEmpty) '… $_partial'];
    voiceStatus.value = lines.join('\n');
  }

  /// Listens without an alarm, only to show levels and text (the microphone test screen).
  Future<void> startTest() async {
    _testing = true;
    _heard.clear();
    _partial = '';
    voiceStatus.value = 'Đang bật micro...';
    await _voice.start();
  }

  Future<void> stopTest() async {
    _testing = false;
    voiceLevel.value = 0;
    voiceStatus.value = '';
    if (_ringing.isEmpty) await _voice.stop();
  }

  void _onVoiceEvent(String event, Object? value) {
    if (_ringing.isEmpty && !_testing) return;
    switch (event) {
      case 'status':
        _show(value == 'listening' ? 'Đang nghe. Nói "tắt chuông đi" hoặc "mười phút nữa báo lại"' : '$value');
      case 'device':
        _device = '$value';
        _show('Đang nghe. Nói "tắt chuông đi" hoặc "mười phút nữa báo lại"');
      case 'level':
        voiceLevel.value = (value as num).toDouble();
      case 'partial':
        _partial = '$value';
        _show('Đang nghe...');
        _handle('$value', isFinal: false);
      case 'final':
        _partial = '';
        _heard.add('"$value"');
        if (_heard.length > 3) _heard.removeAt(0);
        _show('Đang nghe...');
        _handle('$value', isFinal: true);
      case 'error':
        _show('Giọng nói lỗi: $value');
    }
  }

  String _lastRun = '';

  /// Understands [words] and runs the command, if it is one. [isFinal] is false for the running
  /// guess made while the user is still speaking: only commands that end the ringing act on it,
  /// so a half sentence cannot, say, answer "what time is it" twice.
  void _handle(String words, {required bool isFinal}) {
    if (_acted) return;
    final tokens = tokenizeVietnamese(words);
    final m = registry.match(tokens);
    if (m == null) {
      if (isFinal && tokens.length >= 2) {
        final heard = words.trim().toLowerCase();
        if (!unrecognized.value.contains(heard)) unrecognized.value = [heard, ...unrecognized.value].take(6).toList();
      }
      return;
    }
    if (!m.intent.endsRing && !isFinal) return;
    if (!m.intent.endsRing && _lastRun == words) return;
    _lastRun = words;
    final ringing = _ringing.isNotEmpty ? _ringing.first : null;
    final ctx = CommandContext(
      stop: () async => ringing == null ? voiceStatus.value = '(thử) sẽ tắt chuông' : await Alarm.stop(ringing.id),
      snooze: (d) async => ringing == null ? voiceStatus.value = '(thử) sẽ báo lại sau ${d.inMinutes} phút' : await onSnooze(ringing, d),
      say: (t) => voiceStatus.value = t,
      now: _now,
      describeCommands: registry.describe,
    );
    if (m.intent.endsRing && ringing != null) _acted = true;
    unawaited(m.intent.run(ctx, m.args).then((msg) {
      if (msg != null) voiceStatus.value = 'Đã nghe "$words"\n→ $msg';
    }));
  }
}
