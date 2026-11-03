import 'package:flutter/material.dart';

import '../tuya/tuya_client.dart';
import '../tuya/tuya_config.dart';
import '../tuya/tuya_protocol.dart';

/// Stand-in badge for the Tuya brand (not the official artwork): an orange tile with "tuya".
class TuyaLogo extends StatelessWidget {
  final double size;
  const TuyaLogo({super.key, this.size = 44});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: const Color(0xFFFF4800), borderRadius: BorderRadius.circular(size * 0.25)),
      child: Text('tuya', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: size * 0.3, letterSpacing: -0.5)),
    );
  }
}

/// The card on the main screen: shows the plug state and opens the settings.
class TuyaTile extends StatelessWidget {
  final ValueNotifier<TuyaConfig> config;
  final TuyaConfigStore store;
  final TuyaClient client;
  const TuyaTile({super.key, required this.config, required this.store, required this.client});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TuyaConfig>(
      valueListenable: config,
      builder: (context, c, _) {
        final status = !c.complete
            ? 'Chưa kết nối. Bấm để cài đặt ổ cắm thông minh.'
            : c.enabled
                ? '${c.name} • ${c.ip} • bật loa trước ${c.leadSeconds} giây'
                : '${c.name} • ${c.ip} • đang tắt, báo thức không dùng ổ cắm';
        return Card(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: ListTile(
            leading: const TuyaLogo(),
            title: const Text('Tuya • ổ cắm thông minh'),
            subtitle: Text(status),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TuyaPage(config: config, store: store, client: client))),
          ),
        );
      },
    );
  }
}

/// Settings for the Tuya plug: connection details, timing, and a button to try it.
class TuyaPage extends StatefulWidget {
  final ValueNotifier<TuyaConfig> config;
  final TuyaConfigStore store;
  final TuyaClient client;
  const TuyaPage({super.key, required this.config, required this.store, required this.client});

  @override
  State<TuyaPage> createState() => _TuyaPageState();
}

class _TuyaPageState extends State<TuyaPage> {
  late final TextEditingController _name, _id, _ip, _key, _dp;
  late TuyaVersion _version;
  late bool _enabled, _off;
  late double _lead;
  var _showKey = false;
  var _busy = false;
  final _log = <String>[];
  String? _result;
  bool? _resultOk;

  @override
  void initState() {
    super.initState();
    final c = widget.config.value;
    _name = TextEditingController(text: c.name);
    _id = TextEditingController(text: c.deviceId);
    _ip = TextEditingController(text: c.ip);
    _key = TextEditingController(text: c.localKey);
    _dp = TextEditingController(text: c.dp);
    _version = c.version;
    _enabled = c.enabled;
    _off = c.offWhenStopped;
    _lead = c.leadSeconds.toDouble();
  }

  @override
  void dispose() {
    for (final t in [_name, _id, _ip, _key, _dp]) {
      t.dispose();
    }
    super.dispose();
  }

  TuyaConfig _current() => TuyaConfig(
        name: _name.text.trim().isEmpty ? 'Ổ cắm loa' : _name.text.trim(),
        deviceId: _id.text.trim(),
        ip: _ip.text.trim(),
        localKey: _key.text.trim(),
        version: _version,
        dp: _dp.text.trim().isEmpty ? '1' : _dp.text.trim(),
        enabled: _enabled,
        leadSeconds: _lead.round(),
        offWhenStopped: _off,
      );

  Future<void> _save() async {
    final c = _current();
    if (c.enabled && !c.complete) {
      setState(() {
        _result = 'Muốn bật, hãy nhập đủ Device ID, IP và Local key (đúng 16 ký tự).';
        _resultOk = false;
      });
      return;
    }
    await widget.store.save(c);
    widget.config.value = c;
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _try(bool on) async {
    setState(() {
      _busy = true;
      _log.clear();
      _result = null;
    });
    final r = await widget.client.setSwitch(_current(), on, log: (s) => setState(() => _log.add(s)));
    if (mounted) {
      setState(() {
        _busy = false;
        _result = r.message;
        _resultOk = r.ok;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Row(children: [TuyaLogo(size: 30), SizedBox(width: 10), Text('Ổ cắm thông minh Tuya')])),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('Lưu')),
        ),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text(
          'Cắm loa vào ổ cắm Tuya. Trước giờ chuông, app bật ổ cắm để loa khởi động xong rồi chuông mới hát; chuông dừng thì tắt ổ cắm. '
          'App nói chuyện trực tiếp với ổ cắm qua wifi trong nhà (không qua internet), nên điện thoại phải cùng wifi với ổ cắm.',
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Dùng ổ cắm cho báo thức'),
          value: _enabled,
          onChanged: (v) => setState(() => _enabled = v),
        ),
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Tên thiết bị')),
        const SizedBox(height: 8),
        TextField(controller: _id, decoration: const InputDecoration(labelText: 'Device ID', helperText: 'Mã thiết bị, thường bắt đầu bằng "bf" hoặc "eb"')),
        const SizedBox(height: 8),
        TextField(controller: _ip, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Địa chỉ IP của ổ cắm', helperText: 'Ví dụ 192.168.1.50. Nên đặt IP cố định cho ổ cắm trong router')),
        const SizedBox(height: 8),
        TextField(
          controller: _key,
          obscureText: !_showKey,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'Local key (16 ký tự)',
            helperText: 'Khóa cục bộ của thiết bị. Đổi nếu anh xóa và thêm lại ổ cắm trong app Smart Life',
            suffixIcon: IconButton(icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _showKey = !_showKey)),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<TuyaVersion>(
          initialValue: _version,
          decoration: const InputDecoration(labelText: 'Phiên bản giao thức', helperText: 'Thử 3.3 trước; nếu không được thì 3.4. (3.5 chưa hỗ trợ)'),
          items: [for (final v in TuyaVersion.values) DropdownMenuItem(value: v, child: Text(v.label))],
          onChanged: (v) => setState(() => _version = v ?? _version),
        ),
        const SizedBox(height: 8),
        TextField(controller: _dp, decoration: const InputDecoration(labelText: 'Số công tắc (DP)', helperText: 'Hầu hết ổ cắm dùng 1')),
        const Divider(height: 32),
        Text('Thời điểm', style: text.titleMedium),
        Row(children: [
          const SizedBox(width: 130, child: Text('Bật trước chuông')),
          Expanded(child: Slider(value: _lead, min: 0, max: 180, divisions: 36, onChanged: (v) => setState(() => _lead = v))),
          SizedBox(width: 60, child: Text('${_lead.round()} giây', textAlign: TextAlign.end)),
        ]),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Tắt ổ cắm khi chuông dừng'),
          subtitle: const Text('Bấm TẮT, nói "tắt chuông", hoặc hết thời gian phát. Báo lại sau thì giữ ổ cắm bật.'),
          value: _off,
          onChanged: (v) => setState(() => _off = v),
        ),
        const Divider(height: 32),
        Text('Thử kết nối', style: text.titleMedium),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: FilledButton.tonalIcon(onPressed: _busy ? null : () => _try(true), icon: const Icon(Icons.power), label: const Text('Thử BẬT'))),
          const SizedBox(width: 12),
          Expanded(child: FilledButton.tonalIcon(onPressed: _busy ? null : () => _try(false), icon: const Icon(Icons.power_off), label: const Text('Thử TẮT'))),
        ]),
        if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
        if (_log.isNotEmpty || _result != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: SelectableText([..._log, if (_result != null) '', if (_result != null) '${_resultOk == true ? '✓' : '✗'} $_result'].join('\n'), style: const TextStyle(fontSize: 13)),
          ),
        const Divider(height: 32),
        Text('Lấy Device ID và Local key ở đâu?', style: text.titleMedium),
        const SizedBox(height: 4),
        const Text(
          '1. Thêm ổ cắm vào app Smart Life (hoặc Tuya Smart) như bình thường.\n'
          '2. Tạo tài khoản nhà phát triển miễn phí ở iot.tuya.com, tạo một Cloud Project, liên kết tài khoản Smart Life bằng mã QR.\n'
          '3. Chạy công cụ TinyTuya trên máy tính (python -m tinytuya wizard): nó in ra Device ID, Local key và IP của từng thiết bị.\n'
          'Chỉ cần làm một lần. Đóng app Smart Life khi thử: ổ cắm chỉ nhận một kết nối cùng lúc.',
        ),
      ]),
    );
  }
}
