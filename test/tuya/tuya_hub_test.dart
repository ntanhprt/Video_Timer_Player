import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_timer_player/alarm/tuya_alarms.dart';
import 'package:video_timer_player/core/schedule.dart';
import 'package:video_timer_player/tuya/tuya_client.dart';
import 'package:video_timer_player/tuya/tuya_hub.dart';
import 'package:video_timer_player/tuya/tuya_models.dart';
import 'package:video_timer_player/tuya/tuya_protocol.dart';

const _plug = TuyaDevice(id: 'd1', name: 'Loa', deviceId: 'abc', ip: '127.0.0.1', localKey: '0123456789abcdef', version: TuyaVersion.v34, dp: '2');

class _FailingClient extends TuyaClient {
  int calls = 0;
  final int failFor;
  _FailingClient(this.failFor);

  @override
  Future<TuyaResult> setSwitch(TuyaDevice c, bool on, {void Function(String)? log, int? portOverride}) async {
    calls++;
    return calls <= failFor ? const TuyaResult(false, 'mất kết nối') : TuyaResult(true, on ? 'bật' : 'tắt');
  }
}

Future<TuyaHub> hubWith(TuyaClient client, {TuyaData data = const TuyaData()}) async {
  final dir = await Directory.systemTemp.createTemp('hub');
  final store = TuyaStore(File('${dir.path}/t.json'));
  await store.save(data);
  final hub = TuyaHub(store: store, client: client, retryDelay: Duration.zero, clock: () => DateTime(2026, 11, 3, 6, 29, 5));
  await hub.load();
  return hub;
}

void main() {
  test('devices and timers are saved, reloaded, and removed together', () async {
    final hub = await hubWith(TuyaClient());
    await hub.upsertDevice(_plug);
    await hub.upsertRule(const TuyaRule(id: 'r1', deviceId: 'd1', on: true, time: TimeOfDayMin(6, 29), weekdays: {1, 2, 3}));
    await hub.upsertRule(const TuyaRule(id: 'r2', deviceId: 'd1', on: false, time: TimeOfDayMin(7, 15)));
    final again = TuyaHub(store: hub.store, client: TuyaClient());
    await again.load();
    expect(again.data.value.devices.single.dp, '2');
    expect(again.data.value.rulesOf('d1').map((r) => (r.on, r.time.hour, r.time.minute)), [(true, 6, 29), (false, 7, 15)]);
    await hub.removeDevice('d1');
    expect(hub.data.value.devices, isEmpty);
    expect(hub.data.value.rules, isEmpty);
  });

  test('the old single-plug file is read as one device', () async {
    final dir = await Directory.systemTemp.createTemp('legacy');
    final f = File('${dir.path}/t.json');
    await f.writeAsString('{"name":"Cũ","deviceId":"abc","ip":"1.2.3.4","localKey":"0123456789abcdef","version":"3.4","dp":"1","enabled":true}');
    final data = await TuyaStore(f).load();
    expect(data.devices.single.name, 'Cũ');
    expect(data.devices.single.version, TuyaVersion.v34);
  });

  test('a timer retries a failing plug and logs the outcome', () async {
    final client = _FailingClient(2);
    final hub = await hubWith(client, data: const TuyaData(devices: [_plug]));
    final r = await hub.runTimer('d1', true);
    expect(r.ok, isTrue);
    expect(client.calls, 3);
    expect(hub.runs.value.single, contains('Loa BẬT: xong'));
  });

  test('a timer that never works reports failure instead of throwing', () async {
    final hub = await hubWith(_FailingClient(99), data: const TuyaData(devices: [_plug]));
    final r = await hub.runTimer('d1', false);
    expect(r.ok, isFalse);
    expect(hub.runs.value.single, contains('THẤT BẠI'));
    expect((await hub.runTimer('missing', true)).ok, isFalse);
  });

  group('helper alarms for timers', () {
    final now = DateTime(2026, 11, 3, 6, 0);
    const rule = TuyaRule(id: 'r1', deviceId: 'd1', on: true, time: TimeOfDayMin(6, 29), weekdays: {1, 2, 3, 4, 5, 6, 7});

    test('each enabled timer gets its next occurrences, silent and carrying the command', () {
      final alarms = tuyaAlarms(const TuyaData(devices: [_plug], rules: [rule]), now);
      expect(alarms, hasLength(tuyaOccurrences));
      final first = (alarms.values.toList()..sort((a, b) => a.dateTime.compareTo(b.dateTime))).first;
      expect(first.dateTime, DateTime(2026, 11, 3, 6, 29));
      expect(first.assetAudioPath, silentAsset);
      expect(first.loopAudio, isFalse);
      expect(tuyaFromPayload(first.payload), (device: 'd1', on: true));
    });

    test('disabled timers and timers of unknown devices register nothing', () {
      expect(tuyaAlarms(TuyaData(devices: const [_plug], rules: [rule.copyWith(enabled: false)]), now), isEmpty);
      expect(tuyaAlarms(const TuyaData(rules: [rule]), now), isEmpty);
    });

    test('ordinary alarms have no Tuya payload', () {
      expect(tuyaFromPayload(null), isNull);
      expect(tuyaFromPayload('{"holdSeconds":60}'), isNull);
      expect(tuyaFromPayload('garbage'), isNull);
    });
  });
}
