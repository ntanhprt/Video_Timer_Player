import 'dart:async';

import 'package:flutter/foundation.dart';

import 'tuya_client.dart';
import 'tuya_models.dart';

/// The Tuya devices and their timers, plus the commands that switch them.
class TuyaHub {
  final TuyaStore store;
  final TuyaClient client;
  final DateTime Function() _now;
  final Duration retryDelay;

  final data = ValueNotifier<TuyaData>(const TuyaData());

  /// What the timers did lately, newest first, for the Tuya screen.
  final runs = ValueNotifier<List<String>>([]);

  TuyaHub({required this.store, required this.client, DateTime Function()? clock, this.retryDelay = const Duration(seconds: 3)})
      : _now = clock ?? DateTime.now;

  Future<void> load() async => data.value = await store.load();

  Future<void> _set(TuyaData d) async {
    data.value = d;
    await store.save(d);
  }

  Future<void> upsertDevice(TuyaDevice d) {
    final list = [...data.value.devices];
    final i = list.indexWhere((e) => e.id == d.id);
    i < 0 ? list.add(d) : list[i] = d;
    return _set(TuyaData(devices: list, rules: data.value.rules));
  }

  /// Removes the device and every timer that controls it.
  Future<void> removeDevice(String id) => _set(TuyaData(
        devices: [for (final d in data.value.devices) if (d.id != id) d],
        rules: [for (final r in data.value.rules) if (r.deviceId != id) r],
      ));

  Future<void> upsertRule(TuyaRule r) {
    final list = [...data.value.rules];
    final i = list.indexWhere((e) => e.id == r.id);
    i < 0 ? list.add(r) : list[i] = r;
    return _set(TuyaData(devices: data.value.devices, rules: list));
  }

  Future<void> removeRule(String id) => _set(TuyaData(devices: data.value.devices, rules: [for (final r in data.value.rules) if (r.id != id) r]));

  /// Switches one device now.
  Future<TuyaResult> switchDevice(String id, bool on, {void Function(String)? log}) async {
    final d = data.value.device(id);
    if (d == null) return const TuyaResult(false, 'Thiết bị không còn trong danh sách.');
    return client.setSwitch(d, on, log: log);
  }

  String _stamp() {
    final t = _now();
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
  }

  /// Runs a timer: tries up to [attempts] times (wifi may need a moment after the phone wakes up).
  Future<TuyaResult> runTimer(String deviceLocalId, bool on, {int attempts = 3}) async {
    final name = data.value.device(deviceLocalId)?.name ?? '?';
    var last = const TuyaResult(false, 'chưa chạy');
    for (var i = 1; i <= attempts; i++) {
      last = await switchDevice(deviceLocalId, on);
      if (last.ok) break;
      if (i < attempts) await Future<void>.delayed(retryDelay);
    }
    runs.value = ['${_stamp()}  $name ${on ? 'BẬT' : 'TẮT'}: ${last.ok ? 'xong' : 'THẤT BẠI'} — ${last.message}', ...runs.value].take(10).toList();
    return last;
  }
}
