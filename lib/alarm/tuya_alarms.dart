import 'dart:convert';

import 'package:alarm/alarm.dart';

import '../core/schedule.dart';
import '../tuya/tuya_models.dart';
import 'plan.dart';

/// How many coming occurrences of each timer are registered ahead.
const tuyaOccurrences = 7;

/// Silent audio played by the helper alarm that wakes the app to run a timer.
const silentAsset = 'assets/silent.wav';

String tuyaPayload(String deviceId, bool on) => jsonEncode({
      'tuya': {'device': deviceId, 'on': on},
    });

/// Reads the payload of a helper alarm; null for ordinary alarms.
({String device, bool on})? tuyaFromPayload(String? payload) {
  if (payload == null) return null;
  try {
    final t = (jsonDecode(payload) as Map<String, dynamic>)['tuya'];
    if (t is Map<String, dynamic> && t['device'] is String && t['on'] is bool) return (device: t['device'] as String, on: t['on'] as bool);
  } catch (_) {}
  return null;
}

/// The silent native alarms that run the timers: when one rings, the app switches the device and
/// stops it. Registered next to the real alarms so they fire on time even if the app is closed.
Map<int, AlarmSettings> tuyaAlarms(TuyaData data, DateTime now) {
  final out = <int, AlarmSettings>{};
  for (final r in data.rules.where((r) => r.enabled)) {
    final device = data.device(r.deviceId);
    if (device == null) continue;
    var t = nextFire(r.schedule, now);
    for (var k = 0; k < tuyaOccurrences && t != null; k++) {
      final id = alarmIdFor(r.id, k);
      out[id] = AlarmSettings(
        id: id,
        dateTime: t,
        assetAudioPath: silentAsset,
        loopAudio: false,
        vibrate: false,
        warningNotificationOnKill: false,
        androidFullScreenIntent: true,
        androidStopAlarmOnTermination: false,
        androidStaleAfter: const Duration(minutes: 5),
        volumeSettings: VolumeSettings.fixed(),
        notificationSettings: NotificationSettings(title: 'Ổ cắm: ${device.name}', body: r.on ? 'Đang bật' : 'Đang tắt'),
        payload: tuyaPayload(r.deviceId, r.on),
      );
      t = nextFire(r.schedule, t);
    }
  }
  return out;
}
