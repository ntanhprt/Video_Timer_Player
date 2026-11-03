import 'package:flutter/material.dart';

import '../alarm/ring_controller.dart';

/// Pick the microphone used for voice commands and try it: shows the loudness and the text heard.
class MicTestPage extends StatefulWidget {
  final RingController ring;
  const MicTestPage({super.key, required this.ring});

  @override
  State<MicTestPage> createState() => _MicTestPageState();
}

class _MicTestPageState extends State<MicTestPage> {
  List<({int type, String label})> _devices = [];
  int _saved = -1;
  bool _on = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    widget.ring.stopTest();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await widget.ring.bridge.inputDevices();
      final s = await widget.ring.bridge.savedInputType();
      if (!mounted) return;
      setState(() {
        _devices = d;
        _saved = s;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _choose(int type) async {
    await widget.ring.bridge.saveInputType(type);
    setState(() => _saved = type);
    if (_on) await _toggle(restart: true);
  }

  Future<void> _toggle({bool restart = false}) async {
    if (_on || restart) {
      await widget.ring.stopTest();
      await Future<void>.delayed(const Duration(milliseconds: 300)); // let the native loop end
    }
    if (_on && !restart) {
      setState(() => _on = false);
      return;
    }
    setState(() => _on = true);
    await widget.ring.startTest();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Micro & giọng nói')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Nguồn micro', style: text.titleMedium),
        const Text('Chọn micro dùng để nghe lệnh khi chuông kêu. Mặc định là micro của máy.', style: TextStyle(fontSize: 12)),
        if (_error != null) Text('Lỗi: $_error'),
        RadioGroup<int>(
          groupValue: _saved,
          onChanged: (v) => _choose(v ?? -1),
          child: Column(children: [
            const RadioListTile<int>(value: -1, title: Text('Tự động (micro của máy)')),
            for (final d in _devices) RadioListTile<int>(value: d.type, title: Text(d.label)),
          ]),
        ),
        const Divider(height: 32),
        Text('Thử micro', style: text.titleMedium),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _toggle,
          icon: Icon(_on ? Icons.stop : Icons.mic),
          label: Text(_on ? 'Dừng thử' : 'Bắt đầu thử (nói "tắt chuông đi")'),
        ),
        const SizedBox(height: 16),
        ValueListenableBuilder<double>(
          valueListenable: widget.ring.voiceLevel,
          builder: (_, v, _) => LinearProgressIndicator(value: v.clamp(0.0, 1.0), minHeight: 16),
        ),
        const SizedBox(height: 16),
        ValueListenableBuilder<String>(
          valueListenable: widget.ring.voiceStatus,
          builder: (_, v, _) => SelectableText(v.isEmpty ? 'Chưa nghe gì.' : v, style: text.titleMedium),
        ),
      ]),
    );
  }
}
