import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:flutter/foundation.dart';

import 'plan.dart';
import 'voice_bridge.dart';
import 'voice_command.dart';

/// Looks after an alarm while it rings: stops it when its play time is over, and listens for
/// spoken commands ("tắt chuông đi", "mười phút nữa báo lại") with an offline recogniser.
class RingController {
  /// Called to snooze the given ringing alarm.
  final Future<void> Function(AlarmSettings alarm, Duration delay) onSnooze;
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

  RingController({required this.onSnooze, DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  void start() {
    _sub = Alarm.ringing.listen((s) => _onRinging(s.alarms));
    _onRinging(Alarm.ringing.value.alarms);
    // Load the speech model now rather than at the moment the alarm rings.
    unawaited(_voice.prepare().catchError((Object e) => debugPrint('Voice prepare failed: $e')));
  }

  void dispose() {
    _sub?.cancel();
    for (final t in _stopTimers.values) {
      t.cancel();
    }
  }

  void _onRinging(Set<AlarmSettings> ringing) {
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
      case 'final':
        _partial = '';
        _heard.add('"$value"');
        if (_heard.length > 3) _heard.removeAt(0);
        _show('Đang nghe...');
        _handle('$value');
      case 'cmd':
        // From the recogniser limited to the command phrases.
        _handle('$value');
      case 'error':
        _show('Giọng nói lỗi: $value');
    }
  }

  void _handle(String words) {
    if (_acted) return;
    final cmd = parseVoiceCommand(words);
    if (cmd == null) return;
    if (_ringing.isEmpty) {
      if (_testing) voiceStatus.value = '${voiceStatus.value}\n✓ Hiểu là lệnh: $cmd';
      return;
    }
    _acted = true;
    final alarm = _ringing.first;
    switch (cmd) {
      case StopCommand():
        voiceStatus.value = 'Đã nghe lệnh "$words": TẮT CHUÔNG';
        unawaited(Alarm.stop(alarm.id));
      case SnoozeCommand(:final delay):
        voiceStatus.value = 'Đã nghe lệnh "$words": BÁO LẠI SAU ${delay.inMinutes} PHÚT';
        unawaited(onSnooze(alarm, delay));
    }
  }
}
