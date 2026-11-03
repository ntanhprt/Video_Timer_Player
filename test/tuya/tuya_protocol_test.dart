import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_timer_player/tuya/tuya_protocol.dart';

String hex(List<int> b) => b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

void main() {
  // Packets produced by TinyTuya (the reference implementation) with fixed seq/time/nonces.
  final vec = jsonDecode(File('test/tuya/vectors.json').readAsStringSync()) as Map<String, dynamic>;
  final key = utf8.encode('0123456789abcdef');
  const id = 'bf1234567890abcdefxyz1';
  final localNonce = Uint8List.fromList(List.generate(16, (i) => i));
  final remoteNonce = Uint8List.fromList(List.generate(16, (i) => 16 + i));

  test('crc32 matches the standard check value', () {
    expect(crc32(utf8.encode('123456789')), 0xCBF43926);
  });

  test('3.3 control packets are identical to TinyTuya\'s', () {
    expect(
      hex(controlPacket(TuyaVersion.v33, devId: id, localKey: key, dp: '1', value: true, seq: 1, nowSeconds: 1700000000)),
      vec['v33_control_on']['packet'],
    );
    expect(
      hex(controlPacket(TuyaVersion.v33, devId: id, localKey: key, dp: '2', value: false, seq: 7, nowSeconds: 1700000000)),
      vec['v33_dp2_off'],
    );
  });

  test('3.4 session key derivation is identical to TinyTuya\'s', () {
    expect(hex(deriveSessionKey(key, localNonce, remoteNonce)), vec['v34_session_key']);
  });

  test('3.4 handshake packets are identical to TinyTuya\'s', () {
    expect(hex(negotiationStart(key, localNonce, 1)), vec['v34_neg_start']);
    expect(hex(negotiationFinish(key, remoteNonce, 2)), vec['v34_neg_finish']);
  });

  test('3.4 control packet is identical to TinyTuya\'s', () {
    final session = deriveSessionKey(key, localNonce, remoteNonce);
    expect(
      hex(controlPacket(TuyaVersion.v34, devId: id, localKey: key, dp: '1', value: true, seq: 1, nowSeconds: 1700000000, sessionKey: session)),
      vec['v34_control_on']['packet'],
    );
  });

  test('a message survives pack and unpack, and partial data is detected', () {
    final p = packMessage(seq: 9, cmd: 7, payload: [0, 0, 0, 0, 1, 2, 3]);
    expect(messageLength(p.sublist(0, 10)), isNull);
    expect(messageLength(p.sublist(0, p.length - 1)), isNull);
    expect(messageLength(p), p.length);
    final m = unpackMessage(p, hmac: false);
    expect((m.seq, m.cmd, m.retcode), (9, 7, 0));
    expect(m.payload, [1, 2, 3]);
  });

  test('the handshake reply is checked against our nonce', () {
    final good = Uint8List.fromList([...remoteNonce, ...hmacSha256(key, localNonce)]);
    final reply = TuyaMessage(1, TuyaCmd.sessKeyNegResp, 0, aesEcbEncrypt(key, good));
    expect(readNegotiationReply(key, localNonce, reply), remoteNonce);
    final bad = Uint8List.fromList([...remoteNonce, ...hmacSha256(key, remoteNonce)]);
    expect(readNegotiationReply(key, localNonce, TuyaMessage(1, TuyaCmd.sessKeyNegResp, 0, aesEcbEncrypt(key, bad))), isNull);
    expect(readNegotiationReply(utf8.encode('fedcba9876543210'), localNonce, reply), isNull);
  });
}
