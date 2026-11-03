import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'tuya_config.dart';
import 'tuya_protocol.dart';

/// Outcome of a switch command.
class TuyaResult {
  final bool ok;
  final String message;
  const TuyaResult(this.ok, this.message);
  @override
  String toString() => message;
}

/// Reads whole Tuya messages from a socket.
class _Reader {
  final StreamSubscription<Uint8List> _sub;
  var _data = Uint8List(0);
  Completer<void>? _more;
  Object? _error;
  var _closed = false;

  _Reader(Socket s)
      : _sub = s.listen(null) {
    _sub
      ..onData((d) {
        _data = Uint8List.fromList([..._data, ...d]);
        _wake();
      })
      ..onError((Object e) {
        _error = e;
        _wake();
      })
      ..onDone(() {
        _closed = true;
        _wake();
      });
  }

  void _wake() {
    final c = _more;
    _more = null;
    if (c != null && !c.isCompleted) c.complete();
  }

  /// The next complete message, or throws on timeout / closed connection.
  Future<Uint8List> next(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final len = messageLength(_data);
      if (len != null) {
        final msg = _data.sublist(0, len);
        _data = _data.sublist(len);
        return msg;
      }
      if (_error != null) throw _error!;
      if (_closed) throw const SocketException('Thiết bị đã đóng kết nối');
      final left = deadline.difference(DateTime.now());
      if (left.isNegative) throw TimeoutException('Thiết bị không trả lời');
      _more = Completer<void>();
      await _more!.future.timeout(left, onTimeout: () {});
    }
  }

  Future<void> close() => _sub.cancel();
}

/// Talks to a Tuya plug over the local network (no cloud, no internet needed).
class TuyaClient {
  static const port = 6668;

  final Duration connectTimeout;
  final Duration replyTimeout;
  final DateTime Function() _now;
  final Random _random;

  TuyaClient({
    this.connectTimeout = const Duration(seconds: 4),
    this.replyTimeout = const Duration(seconds: 4),
    DateTime Function()? clock,
    Random? random,
  })  : _now = clock ?? DateTime.now,
        _random = random ?? Random.secure();

  /// Switches the plug on or off. [log] receives each step, for the settings screen.
  Future<TuyaResult> setSwitch(TuyaConfig c, bool on, {void Function(String)? log, int? portOverride}) async {
    final say = log ?? (_) {};
    if (!c.complete) return const TuyaResult(false, 'Chưa nhập đủ Device ID, IP và Local key (16 ký tự).');
    final key = utf8.encode(c.localKey);
    Socket? socket;
    _Reader? reader;
    try {
      say('Kết nối ${c.ip}:${portOverride ?? port} ...');
      socket = await Socket.connect(c.ip.trim(), portOverride ?? port, timeout: connectTimeout);
      reader = _Reader(socket);
      say('Đã kết nối, giao thức ${c.version.label}.');
      var seq = 1;
      List<int>? session;
      if (c.version == TuyaVersion.v34) {
        final localNonce = Uint8List.fromList(List.generate(16, (_) => _random.nextInt(256)));
        say('Bắt tay 3.4: gửi nonce...');
        socket.add(negotiationStart(key, localNonce, seq++));
        final reply = unpackMessage(await reader.next(replyTimeout), hmac: true);
        final remoteNonce = readNegotiationReply(key, localNonce, reply);
        if (remoteNonce == null) {
          return const TuyaResult(false, 'Bắt tay thất bại: sai Local key hoặc sai phiên bản giao thức.');
        }
        socket.add(negotiationFinish(key, remoteNonce, seq++));
        session = deriveSessionKey(key, localNonce, remoteNonce);
        say('Bắt tay xong.');
      }
      say(on ? 'Gửi lệnh BẬT...' : 'Gửi lệnh TẮT...');
      socket.add(controlPacket(
        c.version,
        devId: c.deviceId.trim(),
        localKey: key,
        dp: c.dp.trim().isEmpty ? '1' : c.dp.trim(),
        value: on,
        seq: seq,
        nowSeconds: _now().millisecondsSinceEpoch ~/ 1000,
        sessionKey: session,
      ));
      await socket.flush();
      try {
        // Some plugs answer the command, some stay silent: a missing answer is not a failure.
        final m = unpackMessage(await reader.next(replyTimeout), hmac: c.version == TuyaVersion.v34);
        say('Thiết bị trả lời (mã ${m.retcode ?? '-'}).');
        if (m.retcode != null && m.retcode != 0) return TuyaResult(false, 'Thiết bị từ chối lệnh (mã ${m.retcode}).');
        return TuyaResult(true, on ? 'Đã bật ổ cắm.' : 'Đã tắt ổ cắm.');
      } on TimeoutException {
        return TuyaResult(true, '${on ? 'Đã gửi lệnh bật' : 'Đã gửi lệnh tắt'} (thiết bị không phản hồi, kiểm tra xem ổ cắm có đổi trạng thái không).');
      } on SocketException {
        return TuyaResult(true, '${on ? 'Đã gửi lệnh bật' : 'Đã gửi lệnh tắt'} (thiết bị đóng kết nối sau lệnh).');
      }
    } on TimeoutException {
      return const TuyaResult(false, 'Hết thời gian chờ: sai IP, ổ cắm đang tắt nguồn, hoặc app Smart Life đang giữ kết nối với ổ cắm.');
    } on SocketException catch (e) {
      return TuyaResult(false, 'Không kết nối được tới ổ cắm: ${e.message}. Kiểm tra IP và cùng mạng wifi.');
    } catch (e) {
      return TuyaResult(false, 'Lỗi: $e');
    } finally {
      await reader?.close();
      socket?.destroy();
    }
  }
}
