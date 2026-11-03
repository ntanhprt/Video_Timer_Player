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
  StreamSubscription<AlarmSet>? _sub;
  Set<AlarmSettings> _ringing = {};
  bool _acted = false;

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
      unawaited(_voice.stop().catchError((Object _) {}));
    } else if (wasEmpty) {
      _acted = false;
      voiceStatus.value = 'Đang bật micro...';
      unawaited(_voice.start().catchError((Object e) {
        voiceStatus.value = 'Không bật được giọng nói: $e';
      }));
    }
  }

  void _onVoiceEvent(String event, Object? value) {
    if (_ringing.isEmpty) return;
    switch (event) {
      case 'status':
        voiceStatus.value = value == 'listening' ? 'Đang nghe: nói "tắt chuông đi" hoặc "mười phút nữa báo lại"' : '$value';
      case 'level':
        voiceLevel.value = (value as num).toDouble();
      case 'partial':
      case 'final':
        final words = '$value';
        voiceStatus.value = 'Nghe được: "$words"';
        _handle(words);
      case 'error':
        voiceStatus.value = 'Giọng nói lỗi: $value';
    }
  }

  void _handle(String words) {
    if (_acted || _ringing.isEmpty) return;
    final cmd = parseVoiceCommand(words);
    if (cmd == null) return;
    _acted = true;
    final alarm = _ringing.first;
    switch (cmd) {
      case StopCommand():
        voiceStatus.value = 'Đã nghe "$words": tắt chuông';
        unawaited(Alarm.stop(alarm.id));
      case SnoozeCommand(:final delay):
        voiceStatus.value = 'Đã nghe "$words": báo lại sau ${delay.inMinutes} phút';
        unawaited(onSnooze(alarm, delay));
    }
  }
}
