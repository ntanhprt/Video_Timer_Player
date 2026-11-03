import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../core/schedule.dart';
import 'tuya_protocol.dart';

String newTuyaId() => '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${Random().nextInt(1 << 20).toRadixString(36)}';

/// One smart plug (or switch) the app can control over the local network.
class TuyaDevice {
  /// The app's own id for the device (the Tuya `deviceId` below is what the plug itself uses).
  final String id;
  final String name;
  final String deviceId;
  final String ip;
  final String localKey;
  final TuyaVersion version;

  /// Data point of the switch; 1 for almost every plug.
  final String dp;

  const TuyaDevice({
    required this.id,
    this.name = 'Ổ cắm',
    this.deviceId = '',
    this.ip = '',
    this.localKey = '',
    this.version = TuyaVersion.v33,
    this.dp = '1',
  });

  bool get complete => deviceId.trim().isNotEmpty && ip.trim().isNotEmpty && localKey.length == 16;

  TuyaDevice copyWith({String? name, String? deviceId, String? ip, String? localKey, TuyaVersion? version, String? dp}) => TuyaDevice(
        id: id,
        name: name ?? this.name,
        deviceId: deviceId ?? this.deviceId,
        ip: ip ?? this.ip,
        localKey: localKey ?? this.localKey,
        version: version ?? this.version,
        dp: dp ?? this.dp,
      );

  Map<String, Object?> toJson() =>
      {'id': id, 'name': name, 'deviceId': deviceId, 'ip': ip, 'localKey': localKey, 'version': version.label, 'dp': dp};

  factory TuyaDevice.fromJson(Map<String, dynamic> j) => TuyaDevice(
        id: j['id'] as String? ?? newTuyaId(),
        name: j['name'] as String? ?? 'Ổ cắm',
        deviceId: j['deviceId'] as String? ?? '',
        ip: j['ip'] as String? ?? '',
        localKey: j['localKey'] as String? ?? '',
        version: TuyaVersion.fromLabel(j['version'] as String? ?? '3.3'),
        dp: j['dp'] as String? ?? '1',
      );
}

/// "At this time, on these days, switch this device on (or off)": like a timer in the Tuya app.
class TuyaRule {
  final String id;

  /// [TuyaDevice.id] of the device it controls.
  final String deviceId;
  final bool on;
  final TimeOfDayMin time;
  final Set<int> weekdays;
  final bool enabled;

  const TuyaRule({
    required this.id,
    required this.deviceId,
    required this.on,
    required this.time,
    this.weekdays = const {1, 2, 3, 4, 5, 6, 7},
    this.enabled = true,
  });

  TuyaRule copyWith({bool? on, TimeOfDayMin? time, Set<int>? weekdays, bool? enabled}) => TuyaRule(
        id: id,
        deviceId: deviceId,
        on: on ?? this.on,
        time: time ?? this.time,
        weekdays: weekdays ?? this.weekdays,
        enabled: enabled ?? this.enabled,
      );

  ScheduleSpec get schedule => Weekly(time, weekdays);

  Map<String, Object?> toJson() => {
        'id': id,
        'deviceId': deviceId,
        'on': on,
        'h': time.hour,
        'm': time.minute,
        'weekdays': (weekdays.toList()..sort()),
        'enabled': enabled,
      };

  factory TuyaRule.fromJson(Map<String, dynamic> j) => TuyaRule(
        id: j['id'] as String,
        deviceId: j['deviceId'] as String,
        on: j['on'] as bool,
        time: TimeOfDayMin(j['h'] as int, j['m'] as int),
        weekdays: {for (final d in (j['weekdays'] as List)) d as int},
        enabled: j['enabled'] as bool? ?? true,
      );
}

/// Everything the Tuya page edits.
class TuyaData {
  final List<TuyaDevice> devices;
  final List<TuyaRule> rules;
  const TuyaData({this.devices = const [], this.rules = const []});

  TuyaDevice? device(String id) => devices.where((d) => d.id == id).firstOrNull;

  List<TuyaRule> rulesOf(String deviceId) => [for (final r in rules) if (r.deviceId == deviceId) r];

  Map<String, Object?> toJson() => {
        'devices': [for (final d in devices) d.toJson()],
        'rules': [for (final r in rules) r.toJson()],
      };

  factory TuyaData.fromJson(Map<String, dynamic> j) {
    // The first version kept a single plug at the top level of the file.
    if (j['devices'] == null && j['deviceId'] != null) {
      return TuyaData(devices: [TuyaDevice.fromJson({...j, 'id': 'legacy'})]);
    }
    return TuyaData(
      devices: [for (final d in (j['devices'] as List? ?? const [])) TuyaDevice.fromJson(d as Map<String, dynamic>)],
      rules: [for (final r in (j['rules'] as List? ?? const [])) TuyaRule.fromJson(r as Map<String, dynamic>)],
    );
  }
}

/// Keeps devices and timers in a JSON file inside the app's private storage.
class TuyaStore {
  final File file;
  TuyaStore(this.file);

  Future<TuyaData> load() async {
    try {
      if (!await file.exists()) return const TuyaData();
      return TuyaData.fromJson(jsonDecode(await file.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      return const TuyaData();
    }
  }

  Future<void> save(TuyaData d) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(d.toJson()));
  }
}
