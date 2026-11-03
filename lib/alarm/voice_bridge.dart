import 'package:flutter/services.dart';

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

  Future<void> start() => _channel.invokeMethod<void>('start');

  Future<void> stop() => _channel.invokeMethod<void>('stop');

  /// Microphones available right now: `{id, type, label}`.
  Future<List<({int type, String label})>> inputDevices() async {
    final raw = await _channel.invokeListMethod<Map<Object?, Object?>>('inputDevices') ?? [];
    return [for (final m in raw) (type: m['type'] as int, label: m['label'] as String)];
  }

  /// Saved microphone type (an `AudioDeviceInfo` type), or -1 for automatic.
  Future<int> savedInputType() async => await _channel.invokeMethod<int>('savedInputType') ?? -1;

  Future<void> saveInputType(int type) => _channel.invokeMethod<void>('saveInputType', {'type': type});
}
