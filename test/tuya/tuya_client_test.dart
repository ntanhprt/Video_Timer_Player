import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_timer_player/tuya/tuya_client.dart';
import 'package:video_timer_player/tuya/tuya_config.dart';
import 'package:video_timer_player/tuya/tuya_protocol.dart';

const _key = '0123456789abcdef';

/// A pretend plug on the loopback interface that speaks the Tuya protocol.
class FakePlug {
  final TuyaVersion version;
  final bool answers;
  late final ServerSocket server;
  final received = <String>[];
  FakePlug(this.version, {this.answers = true});

  int get port => server.port;

  Future<void> start() async {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_serve);
  }

  Future<void> stop() => server.close();

  void _serve(Socket s) {
    final key = utf8.encode(_key);
    var buf = Uint8List(0);
    List<int>? localNonce;
    List<int>? session;
    final remoteNonce = Uint8List.fromList(List.generate(16, (i) => 100 + i));
    s.listen((d) {
      buf = Uint8List.fromList([...buf, ...d]);
      while (true) {
        final len = messageLength(buf);
        if (len == null) return;
        final raw = buf.sublist(0, len);
        buf = buf.sublist(len);
        final m = unpackMessage(raw, hmac: version == TuyaVersion.v34);
        if (m.cmd == TuyaCmd.sessKeyNegStart) {
          localNonce = aesEcbDecrypt(key, m.payload).sublist(0, 16);
          final reply = aesEcbEncrypt(key, [...remoteNonce, ...hmacSha256(key, localNonce!)]);
          s.add(packMessage(seq: m.seq, cmd: TuyaCmd.sessKeyNegResp, payload: [0, 0, 0, 0, ...reply], hmacKey: key));
        } else if (m.cmd == TuyaCmd.sessKeyNegFinish) {
          session = deriveSessionKey(key, localNonce!, remoteNonce);
        } else if (m.cmd == TuyaCmd.control) {
          final plain = aesEcbDecrypt(key, m.payload.sublist(15));
          received.add(utf8.decode(plain));
          if (answers) s.add(packMessage(seq: m.seq, cmd: m.cmd, payload: [0, 0, 0, 0]));
        } else if (m.cmd == TuyaCmd.controlNew) {
          final plain = aesEcbDecrypt(session!, m.payload);
          received.add(utf8.decode(plain.sublist(15)));
          if (answers) s.add(packMessage(seq: m.seq, cmd: m.cmd, payload: [0, 0, 0, 0], hmacKey: session));
        }
      }
    });
  }
}

TuyaConfig config(TuyaVersion v) => TuyaConfig(deviceId: 'abc123', ip: '127.0.0.1', localKey: _key, version: v);

void main() {
  for (final v in TuyaVersion.values) {
    test('${v.label}: switches the plug on and off and reports success', () async {
      final plug = FakePlug(v);
      await plug.start();
      final client = TuyaClient(clock: () => DateTime.fromMillisecondsSinceEpoch(1700000000000));
      final steps = <String>[];
      final on = await client.setSwitch(config(v), true, portOverride: plug.port, log: steps.add);
      final off = await client.setSwitch(config(v), false, portOverride: plug.port);
      await plug.stop();
      expect(on.ok, isTrue, reason: on.message);
      expect(off.ok, isTrue, reason: off.message);
      expect(plug.received, hasLength(2));
      expect(plug.received[0], contains('"1":true'));
      expect(plug.received[1], contains('"1":false'));
      expect(steps.join('\n'), contains('BẬT'));
    });
  }

  test('a plug that stays silent still counts as sent', () async {
    final plug = FakePlug(TuyaVersion.v33, answers: false);
    await plug.start();
    final client = TuyaClient(replyTimeout: const Duration(milliseconds: 300));
    final r = await client.setSwitch(config(TuyaVersion.v33), true, portOverride: plug.port);
    await plug.stop();
    expect(r.ok, isTrue);
    expect(r.message, contains('không phản hồi'));
  });

  test('3.4 with the wrong local key fails the handshake with a clear message', () async {
    final plug = FakePlug(TuyaVersion.v34);
    await plug.start();
    final client = TuyaClient(replyTimeout: const Duration(seconds: 1));
    final r = await client.setSwitch(config(TuyaVersion.v34).copyWith(localKey: 'fedcba9876543210'), true, portOverride: plug.port);
    await plug.stop();
    expect(r.ok, isFalse);
  });

  test('nothing listening: fails fast with a readable message', () async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = s.port;
    await s.close();
    final r = await TuyaClient(connectTimeout: const Duration(seconds: 1)).setSwitch(config(TuyaVersion.v33), true, portOverride: port);
    expect(r.ok, isFalse);
    expect(r.message, isNotEmpty);
  });

  test('missing settings are reported without touching the network', () async {
    final r = await TuyaClient().setSwitch(const TuyaConfig(), true);
    expect(r.ok, isFalse);
    expect(r.message, contains('Local key'));
  });

  test('config round-trips through its store', () async {
    final dir = await Directory.systemTemp.createTemp('tuya');
    final store = TuyaConfigStore(File('${dir.path}/t.json'));
    expect((await store.load()).complete, isFalse);
    final c = config(TuyaVersion.v34).copyWith(enabled: true, leadSeconds: 45, dp: '2');
    await store.save(c);
    final back = await store.load();
    expect((back.deviceId, back.version, back.enabled, back.leadSeconds, back.dp), ('abc123', TuyaVersion.v34, true, 45, '2'));
    await dir.delete(recursive: true);
  });
}
