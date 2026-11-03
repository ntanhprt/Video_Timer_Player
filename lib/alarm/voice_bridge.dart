import 'package:flutter/services.dart';

import 'voice_command.dart';

/// Offline speech recognition running in the native side (Vosk with a bundled Vietnamese model).
///
/// Events: `status` ("listening" or a message), `level` (0..1 microphone loudness),
/// `partial` / `final` (recognised text), `error`.
class VoiceBridge {
  static const _channel = MethodChannel('vn.aisolutions/voice');

  VoiceBridge(void Function(String event, Object? value) onEvent) {
    _channel.setMethodCallHandler((call) async => onEvent(call.method, call.arguments));
  }

  /// Loads the model ahead of time so listening starts instantly when an alarm rings.
  Future<void> prepare() => _channel.invokeMethod<void>('prepare');

  Future<void> start() => _channel.invokeMethod<void>('start', {'grammar': voiceGrammar()});

  Future<void> stop() => _channel.invokeMethod<void>('stop');
}
