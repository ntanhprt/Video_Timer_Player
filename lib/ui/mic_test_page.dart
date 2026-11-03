import 'package:flutter/material.dart';

import '../alarm/commands/custom.dart';
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

  /// Asks what the heard sentence should do, then remembers it as a command.
  Future<void> _teach(String heard) async {
    final phrase = TextEditingController(text: heard);
    final minutes = TextEditingController(text: '10');
    var action = 'stop';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Dạy lệnh mới'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: phrase, decoration: const InputDecoration(labelText: 'Khi anh nói câu này (sửa lại cho đúng nếu app nghe sai)')),
            RadioGroup<String>(
              groupValue: action,
              onChanged: (v) => setLocal(() => action = v ?? action),
              child: const Column(children: [
                RadioListTile<String>(value: 'stop', title: Text('Tắt chuông')),
                RadioListTile<String>(value: 'snooze', title: Text('Báo lại sau...')),
              ]),
            ),
            if (action == 'snooze')
              TextField(controller: minutes, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Số phút')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lưu lệnh')),
          ],
        ),
      ),
    );
    if (ok == true) await widget.ring.teach(phrase.text, action, minutes: int.tryParse(minutes.text) ?? 10);
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
        const Divider(height: 32),
        Text('Câu chưa hiểu — bấm để dạy app', style: text.titleMedium),
        ValueListenableBuilder<List<String>>(
          valueListenable: widget.ring.unrecognized,
          builder: (_, list, _) => list.isEmpty
              ? const Padding(padding: EdgeInsets.all(8), child: Text('Chưa có. Nói một câu app chưa hiểu, nó sẽ hiện ở đây.'))
              : Column(children: [
                  for (final s in list)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.school),
                      title: Text('"$s"'),
                      subtitle: const Text('Bấm để chọn câu này làm lệnh gì'),
                      onTap: () => _teach(s),
                    ),
                ]),
        ),
        const Divider(height: 32),
        Text('Lệnh anh đã dạy', style: text.titleMedium),
        ValueListenableBuilder<List<CustomCommand>>(
          valueListenable: widget.ring.customCommands,
          builder: (_, list, _) => list.isEmpty
              ? const Padding(padding: EdgeInsets.all(8), child: Text('Chưa có lệnh nào.'))
              : Column(children: [
                  for (final c in list)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.record_voice_over),
                      title: Text('"${c.phrase}"'),
                      subtitle: Text('→ ${c.label}'),
                      trailing: IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Xóa lệnh', onPressed: () => widget.ring.forget(c)),
                    ),
                ]),
        ),
        const Divider(height: 32),
        Text('Lệnh có sẵn', style: text.titleMedium),
        for (final line in widget.ring.registry.describe()) Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text('• $line')),
      ]),
    );
  }
}
