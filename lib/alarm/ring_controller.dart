import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'plan.dart';
import 'voice_command.dart';

/// Looks after an alarm while it rings: stops it when its play time is over, and listens for
/// spoken commands ("tắt chuông đi", "mười phút nữa báo lại").
class RingController {
  /// Called to snooze the given ringing alarm.
  final Future<void> Function(AlarmSettings alarm, Duration delay) onSnooze;
  final DateTime Function() _now;

  /// What the ringing screen shows about the microphone.
  final voiceStatus = ValueNotifier<String>('');

  final _stopTimers = <int, Timer>{};
  final _speech = SpeechToText();
  StreamSubscription<AlarmSet>? _sub;
  Set<AlarmSettings> _ringing = {};
  bool _speechReady = false;
  bool _listening = false;
  bool _acted = false;
  String? _localeId;

  RingController({required this.onSnooze, DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  void start() {
    _sub = Alarm.ringing.listen((s) => _onRinging(s.alarms));
    _onRinging(Alarm.ringing.value.alarms);
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
      _stopTimers.putIfAbsent(a.id, () {
        final hold = holdFromPayload(a.payload);
        if (hold == null) return Timer(const Duration(days: 365), () {});
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
      if (_listening) unawaited(_speech.cancel());
      _listening = false;
    } else if (wasEmpty) {
      _acted = false;
      unawaited(_listen());
    }
  }

  Future<void> _listen() async {
    if (_ringing.isEmpty || _acted || _listening) return;
    try {
      if (!_speechReady) {
        _speechReady = await _speech.initialize(
          onStatus: _onStatus,
          onError: (e) {
            debugPrint('Speech error: ${e.errorMsg}');
            _restartSoon();
          },
        );
        if (_speechReady) {
          final locales = await _speech.locales();
          _localeId = locales.where((l) => l.localeId.toLowerCase().startsWith('vi')).map((l) => l.localeId).firstOrNull;
        }
      }
      if (!_speechReady) {
        voiceStatus.value = 'Không dùng được giọng nói (chưa cấp quyền micro hoặc máy không hỗ trợ).';
        return;
      }
      _listening = true;
      voiceStatus.value = 'Đang nghe: nói "tắt chuông đi" hoặc "mười phút nữa báo lại"';
      await _speech.listen(
        onResult: (r) {
          final words = r.recognizedWords;
          if (words.isEmpty) return;
          voiceStatus.value = 'Nghe được: "$words"';
          _handle(words);
        },
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          localeId: _localeId,
          listenFor: const Duration(seconds: 60),
          pauseFor: const Duration(seconds: 8),
        ),
      );
    } catch (e) {
      debugPrint('Speech start failed: $e');
      _listening = false;
      _restartSoon();
    }
  }

  void _onStatus(String status) {
    if (status == 'done' || status == 'notListening') {
      _listening = false;
      _restartSoon();
    }
  }

  void _restartSoon() {
    if (_ringing.isEmpty || _acted) return;
    Future<void>.delayed(const Duration(milliseconds: 800), _listen);
  }

  void _handle(String words) {
    if (_acted || _ringing.isEmpty) return;
    final cmd = parseVoiceCommand(words);
    if (cmd == null) return;
    _acted = true;
    final alarm = _ringing.first;
    unawaited(_speech.cancel());
    _listening = false;
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
