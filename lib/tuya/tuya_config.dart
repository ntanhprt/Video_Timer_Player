import 'dart:convert';
import 'dart:io';

import 'tuya_protocol.dart';

/// The smart plug the alarm switches on before it rings (and off when it stops).
class TuyaConfig {
  final String name;
  final String deviceId;
  final String ip;
  final String localKey;
  final TuyaVersion version;

  /// Data point of the switch; 1 for almost every plug.
  final String dp;

  /// Master switch: when false the alarms ignore the plug.
  final bool enabled;

  /// How long before the alarm rings the plug is switched on, so the speaker has time to start.
  final int leadSeconds;

  /// Switch the plug off again when the alarm stops.
  final bool offWhenStopped;

  const TuyaConfig({
    this.name = 'Ổ cắm loa',
    this.deviceId = '',
    this.ip = '',
    this.localKey = '',
    this.version = TuyaVersion.v33,
    this.dp = '1',
    this.enabled = false,
    this.leadSeconds = 30,
    this.offWhenStopped = true,
  });

  bool get complete => deviceId.trim().isNotEmpty && ip.trim().isNotEmpty && localKey.length == 16;

  TuyaConfig copyWith({
    String? name,
    String? deviceId,
    String? ip,
    String? localKey,
    TuyaVersion? version,
    String? dp,
    bool? enabled,
    int? leadSeconds,
    bool? offWhenStopped,
  }) =>
      TuyaConfig(
        name: name ?? this.name,
        deviceId: deviceId ?? this.deviceId,
        ip: ip ?? this.ip,
        localKey: localKey ?? this.localKey,
        version: version ?? this.version,
        dp: dp ?? this.dp,
        enabled: enabled ?? this.enabled,
        leadSeconds: leadSeconds ?? this.leadSeconds,
        offWhenStopped: offWhenStopped ?? this.offWhenStopped,
      );

  Map<String, Object?> toJson() => {
        'name': name,
        'deviceId': deviceId,
        'ip': ip,
        'localKey': localKey,
        'version': version.label,
        'dp': dp,
        'enabled': enabled,
        'leadSeconds': leadSeconds,
        'offWhenStopped': offWhenStopped,
      };

  factory TuyaConfig.fromJson(Map<String, dynamic> j) => TuyaConfig(
        name: j['name'] as String? ?? 'Ổ cắm loa',
        deviceId: j['deviceId'] as String? ?? '',
        ip: j['ip'] as String? ?? '',
        localKey: j['localKey'] as String? ?? '',
        version: TuyaVersion.fromLabel(j['version'] as String? ?? '3.3'),
        dp: j['dp'] as String? ?? '1',
        enabled: j['enabled'] as bool? ?? false,
        leadSeconds: j['leadSeconds'] as int? ?? 30,
        offWhenStopped: j['offWhenStopped'] as bool? ?? true,
      );
}

/// Keeps the plug settings in a JSON file inside the app's private storage.
class TuyaConfigStore {
  final File file;
  TuyaConfigStore(this.file);

  Future<TuyaConfig> load() async {
    try {
      if (!await file.exists()) return const TuyaConfig();
      return TuyaConfig.fromJson(jsonDecode(await file.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      return const TuyaConfig();
    }
  }

  Future<void> save(TuyaConfig c) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(c.toJson()));
  }
}
