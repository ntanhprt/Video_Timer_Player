import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart';

/// The Tuya LAN protocol (versions 3.3 and 3.4), byte for byte compatible with TinyTuya.
/// Pure functions only: nothing here touches the network.
enum TuyaVersion {
  v33('3.3'),
  v34('3.4');

  final String label;
  const TuyaVersion(this.label);

  static TuyaVersion fromLabel(String s) => values.firstWhere((v) => v.label == s, orElse: () => v33);
}

/// Message types used here.
abstract final class TuyaCmd {
  static const sessKeyNegStart = 3;
  static const sessKeyNegResp = 4;
  static const sessKeyNegFinish = 5;
  static const control = 7;
  static const controlNew = 13;
}

const _prefix = 0x000055AA;
const _suffix = 0x0000AA55;

Uint8List _u32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.big);

int _readU32(Uint8List b, int o) => b.buffer.asByteData(b.offsetInBytes).getUint32(o, Endian.big);

final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int crc32(List<int> data) {
  var c = 0xFFFFFFFF;
  for (final b in data) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

Uint8List hmacSha256(List<int> key, List<int> data) => Uint8List.fromList(crypto.Hmac(crypto.sha256, key).convert(data).bytes);

Uint8List aesEcbEncrypt(List<int> key, List<int> data, {bool pad = true}) {
  final input = Uint8List.fromList(data);
  if (pad) {
    final c = PaddedBlockCipher('AES/ECB/PKCS7')..init(true, PaddedBlockCipherParameters<KeyParameter, Null>(KeyParameter(Uint8List.fromList(key)), null));
    return c.process(input);
  }
  assert(input.length % 16 == 0);
  final c = ECBBlockCipher(AESEngine())..init(true, KeyParameter(Uint8List.fromList(key)));
  final out = Uint8List(input.length);
  for (var o = 0; o < input.length; o += 16) {
    c.processBlock(input, o, out, o);
  }
  return out;
}

/// Decrypts whole blocks; padding is stripped when it is valid PKCS7, otherwise left as is.
Uint8List aesEcbDecrypt(List<int> key, List<int> data) {
  final input = Uint8List.fromList(data);
  final c = ECBBlockCipher(AESEngine())..init(false, KeyParameter(Uint8List.fromList(key)));
  final out = Uint8List(input.length - input.length % 16);
  for (var o = 0; o < out.length; o += 16) {
    c.processBlock(input, o, out, o);
  }
  if (out.isEmpty) return out;
  final n = out.last;
  if (n >= 1 && n <= 16 && n <= out.length && out.sublist(out.length - n).every((b) => b == n)) {
    return out.sublist(0, out.length - n);
  }
  return out;
}

/// One 55AA message: prefix, sequence, command, length, payload, CRC32 (or HMAC-SHA256 when
/// [hmacKey] is given, as in 3.4), suffix.
Uint8List packMessage({required int seq, required int cmd, required List<int> payload, List<int>? hmacKey}) {
  final trailer = hmacKey == null ? 4 : 32;
  final head = BytesBuilder()
    ..add(_u32(_prefix))
    ..add(_u32(seq))
    ..add(_u32(cmd))
    ..add(_u32(payload.length + trailer + 4))
    ..add(payload);
  final body = head.toBytes();
  final out = BytesBuilder()
    ..add(body)
    ..add(hmacKey == null ? _u32(crc32(body)) : hmacSha256(hmacKey, body))
    ..add(_u32(_suffix));
  return out.toBytes();
}

/// A message received from the device.
class TuyaMessage {
  final int seq;
  final int cmd;

  /// 0 means success; null when the device sent none.
  final int? retcode;

  /// Still encrypted.
  final Uint8List payload;
  const TuyaMessage(this.seq, this.cmd, this.retcode, this.payload);
}

/// How many bytes the first message in [data] takes, or null when it has not fully arrived.
int? messageLength(Uint8List data) {
  if (data.length < 16) return null;
  if (_readU32(data, 0) != _prefix) throw const FormatException('Không phải gói tin Tuya');
  final total = 16 + _readU32(data, 12);
  return data.length >= total ? total : null;
}

/// Reads one complete message (as returned by [messageLength]); [hmac] is true for 3.4.
TuyaMessage unpackMessage(Uint8List data, {required bool hmac}) {
  final len = _readU32(data, 12);
  final trailer = hmac ? 32 : 4;
  var inner = data.sublist(16, 16 + len - trailer - 4);
  int? retcode;
  if (inner.length >= 4) {
    final r = _readU32(inner, 0);
    if ((r & 0xFFFFFF00) == 0) {
      retcode = r;
      inner = inner.sublist(4);
    }
  }
  return TuyaMessage(_readU32(data, 4), _readU32(data, 8), retcode, inner);
}

const _versionHeaderZeros = 12;

List<int> _versionHeader(TuyaVersion v) => [...ascii.encode(v.label), ...List.filled(_versionHeaderZeros, 0)];

/// JSON that switches data point [dp] of the device.
String controlJson(TuyaVersion v, {required String devId, required String dp, required bool value, required int nowSeconds}) {
  return switch (v) {
    TuyaVersion.v33 => jsonEncode({'devId': devId, 'uid': devId, 't': '$nowSeconds', 'dps': {dp: value}}),
    TuyaVersion.v34 => jsonEncode({'protocol': 5, 't': nowSeconds, 'data': {'dps': {dp: value}}}),
  };
}

/// The packet that switches a data point. For 3.4 [sessionKey] (from [deriveSessionKey]) is needed.
Uint8List controlPacket(
  TuyaVersion v, {
  required String devId,
  required List<int> localKey,
  required String dp,
  required bool value,
  required int seq,
  required int nowSeconds,
  List<int>? sessionKey,
}) {
  final json = utf8.encode(controlJson(v, devId: devId, dp: dp, value: value, nowSeconds: nowSeconds));
  switch (v) {
    case TuyaVersion.v33:
      final enc = aesEcbEncrypt(localKey, json);
      return packMessage(seq: seq, cmd: TuyaCmd.control, payload: [..._versionHeader(v), ...enc]);
    case TuyaVersion.v34:
      final key = sessionKey ?? (throw ArgumentError('3.4 needs a session key'));
      final enc = aesEcbEncrypt(key, [..._versionHeader(v), ...json]);
      return packMessage(seq: seq, cmd: TuyaCmd.controlNew, payload: enc, hmacKey: key);
  }
}

/// 3.4 handshake, step 1: our random nonce, encrypted with the local key.
Uint8List negotiationStart(List<int> localKey, List<int> localNonce, int seq) =>
    packMessage(seq: seq, cmd: TuyaCmd.sessKeyNegStart, payload: aesEcbEncrypt(localKey, localNonce), hmacKey: localKey);

/// Reads the device's answer to step 1: its nonce, after checking that it knows our nonce.
/// Returns null when the answer is wrong (wrong local key, wrong version).
Uint8List? readNegotiationReply(List<int> localKey, List<int> localNonce, TuyaMessage reply) {
  if (reply.cmd != TuyaCmd.sessKeyNegResp) return null;
  final p = aesEcbDecrypt(localKey, reply.payload);
  if (p.length < 48) return null;
  final expected = hmacSha256(localKey, localNonce);
  for (var i = 0; i < 32; i++) {
    if (p[16 + i] != expected[i]) return null;
  }
  return Uint8List.fromList(p.sublist(0, 16));
}

/// 3.4 handshake, step 3: proves that we know the key by returning the HMAC of its nonce.
Uint8List negotiationFinish(List<int> localKey, List<int> remoteNonce, int seq) =>
    packMessage(seq: seq, cmd: TuyaCmd.sessKeyNegFinish, payload: aesEcbEncrypt(localKey, hmacSha256(localKey, remoteNonce)), hmacKey: localKey);

/// The key used for the rest of a 3.4 connection.
Uint8List deriveSessionKey(List<int> localKey, List<int> localNonce, List<int> remoteNonce) {
  final x = [for (var i = 0; i < 16; i++) localNonce[i] ^ remoteNonce[i]];
  return aesEcbEncrypt(localKey, x, pad: false);
}
