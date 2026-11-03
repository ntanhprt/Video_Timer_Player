import 'package:flutter/material.dart';

import '../core/schedule.dart';
import '../tuya/tuya_hub.dart';
import '../tuya/tuya_models.dart';
import '../tuya/tuya_protocol.dart';
import 'alarm_summary.dart';
import 'tuya_guide_page.dart';

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

String ruleLabel(TuyaRule r) => '${timeLabel(r.time)}  ${r.on ? 'BẬT' : 'TẮT'}  •  ${repeatLabel(r.weekdays)}';

/// The card on the main screen: how many devices and timers there are, opens the Tuya screen.
class TuyaTile extends StatelessWidget {
  final TuyaHub hub;
  const TuyaTile({super.key, required this.hub});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TuyaData>(
      valueListenable: hub.data,
      builder: (context, d, _) {
        final active = d.rules.where((r) => r.enabled).length;
        final status = d.devices.isEmpty
            ? 'Chưa có thiết bị. Bấm để thêm ổ cắm thông minh.'
            : '${d.devices.length} thiết bị • $active hẹn giờ đang bật';
        return Card(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: ListTile(
            leading: const TuyaLogo(),
            title: const Text('Tuya • thiết bị thông minh'),
            subtitle: Text(status),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TuyaPage(hub: hub))),
          ),
        );
      },
    );
  }
}

/// The list of devices, each with quick on/off and its timers.
class TuyaPage extends StatelessWidget {
  final TuyaHub hub;
  const TuyaPage({super.key, required this.hub});

  void _edit(BuildContext context, [TuyaDevice? d]) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TuyaDevicePage(hub: hub, device: d)));

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [TuyaLogo(size: 30), SizedBox(width: 10), Text('Thiết bị Tuya')]),
        actions: [
          IconButton(
            tooltip: 'Hướng dẫn kết nối',
            icon: const Icon(Icons.help_outline),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TuyaGuidePage())),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context),
        icon: const Icon(Icons.add),
        label: const Text('Thêm thiết bị'),
      ),
      body: ValueListenableBuilder<TuyaData>(
        valueListenable: hub.data,
        builder: (context, data, _) => ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 96), children: [
          if (data.devices.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                const Text('Chưa có thiết bị nào. Bấm "Thêm thiết bị" để nhập ổ cắm Tuya (Device ID, IP, Local key).'),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TuyaGuidePage())),
                  icon: const Icon(Icons.help_outline),
                  label: const Text('Lấy các thông tin này ở đâu?'),
                ),
              ]),
            ),
          for (final d in data.devices) _DeviceCard(hub: hub, device: d, rules: data.rulesOf(d.id), onEdit: () => _edit(context, d)),
          ValueListenableBuilder<List<String>>(
            valueListenable: hub.runs,
            builder: (_, runs, _) => runs.isEmpty
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Hẹn giờ đã chạy gần đây', style: text.titleSmall),
                      for (final r in runs) SelectableText(r, style: const TextStyle(fontSize: 12)),
                    ]),
                  ),
          ),
        ]),
      ),
    );
  }
}

class _DeviceCard extends StatefulWidget {
  final TuyaHub hub;
  final TuyaDevice device;
  final List<TuyaRule> rules;
  final VoidCallback onEdit;
  const _DeviceCard({required this.hub, required this.device, required this.rules, required this.onEdit});

  @override
  State<_DeviceCard> createState() => _DeviceCardState();
}

class _DeviceCardState extends State<_DeviceCard> {
  var _busy = false;
  String? _result;

  Future<void> _switch(bool on) async {
    setState(() {
      _busy = true;
      _result = null;
    });
    final r = await widget.hub.switchDevice(widget.device.id, on);
    if (mounted) {
      setState(() {
        _busy = false;
        _result = '${r.ok ? '✓' : '✗'} ${r.message}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.device;
    final sorted = [...widget.rules]..sort((a, b) => a.time.totalMinutes.compareTo(b.time.totalMinutes));
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            onTap: widget.onEdit,
            child: Row(children: [
              const Icon(Icons.power, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(d.name, style: Theme.of(context).textTheme.titleMedium),
                  Text(d.complete ? '${d.ip} • giao thức ${d.version.label}' : 'Chưa nhập đủ thông tin kết nối', style: const TextStyle(fontSize: 12)),
                ]),
              ),
              const Icon(Icons.edit, size: 18),
            ]),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: FilledButton.tonalIcon(onPressed: _busy || !d.complete ? null : () => _switch(true), icon: const Icon(Icons.power), label: const Text('BẬT'))),
            const SizedBox(width: 8),
            Expanded(child: FilledButton.tonalIcon(onPressed: _busy || !d.complete ? null : () => _switch(false), icon: const Icon(Icons.power_off), label: const Text('TẮT'))),
          ]),
          if (_busy) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
          if (_result != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_result!, style: const TextStyle(fontSize: 12))),
          const Divider(height: 20),
          if (sorted.isEmpty) const Text('Chưa có hẹn giờ. Mở thiết bị để thêm giờ bật / tắt.', style: TextStyle(fontSize: 12)),
          for (final r in sorted)
            Row(children: [
              Expanded(child: Text(ruleLabel(r), style: TextStyle(fontWeight: FontWeight.w600, color: r.enabled ? null : Theme.of(context).disabledColor))),
              Switch(value: r.enabled, onChanged: (v) => widget.hub.upsertRule(r.copyWith(enabled: v))),
            ]),
        ]),
      ),
    );
  }
}

/// Add or edit one device: connection details, a test, and its timers.
class TuyaDevicePage extends StatefulWidget {
  final TuyaHub hub;
  final TuyaDevice? device;
  const TuyaDevicePage({super.key, required this.hub, this.device});

  @override
  State<TuyaDevicePage> createState() => _TuyaDevicePageState();
}

class _TuyaDevicePageState extends State<TuyaDevicePage> {
  late final String _id = widget.device?.id ?? newTuyaId();
  late final TextEditingController _name, _devId, _ip, _key, _dp;
  late TuyaVersion _version;
  var _showKey = false;
  var _busy = false;
  final _log = <String>[];
  String? _result;
  bool? _ok;

  @override
  void initState() {
    super.initState();
    final d = widget.device;
    _name = TextEditingController(text: d?.name ?? 'Ổ cắm loa');
    _devId = TextEditingController(text: d?.deviceId ?? '');
    _ip = TextEditingController(text: d?.ip ?? '');
    _key = TextEditingController(text: d?.localKey ?? '');
    _dp = TextEditingController(text: d?.dp ?? '1');
    _version = d?.version ?? TuyaVersion.v33;
  }

  @override
  void dispose() {
    for (final t in [_name, _devId, _ip, _key, _dp]) {
      t.dispose();
    }
    super.dispose();
  }

  TuyaDevice _current() => TuyaDevice(
        id: _id,
        name: _name.text.trim().isEmpty ? 'Ổ cắm' : _name.text.trim(),
        deviceId: _devId.text.trim(),
        ip: _ip.text.trim(),
        localKey: _key.text.trim(),
        version: _version,
        dp: _dp.text.trim().isEmpty ? '1' : _dp.text.trim(),
      );

  Future<void> _save() async {
    await widget.hub.upsertDevice(_current());
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _try(bool on) async {
    setState(() {
      _busy = true;
      _log.clear();
      _result = null;
    });
    final r = await widget.hub.client.setSwitch(_current(), on, log: (s) => setState(() => _log.add(s)));
    if (mounted) {
      setState(() {
        _busy = false;
        _result = r.message;
        _ok = r.ok;
      });
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa thiết bị?'),
        content: const Text('Các hẹn giờ của thiết bị này cũng bị xóa.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Giữ lại')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Xóa')),
        ],
      ),
    );
    if (ok == true) {
      await widget.hub.removeDevice(_id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _editRule([TuyaRule? r]) async {
    if (widget.hub.data.value.device(_id) == null) await widget.hub.upsertDevice(_current());
    if (!mounted) return;
    final result = await showDialog<TuyaRule>(
      context: context,
      builder: (_) => _RuleDialog(rule: r ?? TuyaRule(id: newTuyaId(), deviceId: _id, on: true, time: const TimeOfDayMin(6, 29))),
    );
    if (result != null) await widget.hub.upsertRule(result);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device == null ? 'Thêm thiết bị' : 'Sửa thiết bị'),
        actions: [
          IconButton(
            tooltip: 'Hướng dẫn kết nối',
            icon: const Icon(Icons.help_outline),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TuyaGuidePage())),
          ),
          if (widget.device != null) IconButton(tooltip: 'Xóa', icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('Lưu thiết bị')),
        ),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Tên thiết bị', helperText: 'Ví dụ: Loa phòng ngủ')),
        const SizedBox(height: 8),
        TextField(controller: _devId, autocorrect: false, decoration: const InputDecoration(labelText: 'Device ID', helperText: 'Mã thiết bị (xem "Hướng dẫn kết nối")')),
        const SizedBox(height: 8),
        TextField(
          controller: _ip,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Địa chỉ IP của ổ cắm', helperText: 'Ví dụ 192.168.1.50. Nên đặt IP cố định cho ổ cắm trong router'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _key,
          obscureText: !_showKey,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'Local key (16 ký tự)',
            helperText: 'Đổi nếu anh xóa và thêm lại ổ cắm trong app Tuya',
            suffixIcon: IconButton(icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _showKey = !_showKey)),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<TuyaVersion>(
          initialValue: _version,
          decoration: const InputDecoration(labelText: 'Phiên bản giao thức', helperText: 'Thử 3.3 trước; không được thì 3.4. (3.5 chưa hỗ trợ)'),
          items: [for (final v in TuyaVersion.values) DropdownMenuItem(value: v, child: Text(v.label))],
          onChanged: (v) => setState(() => _version = v ?? _version),
        ),
        const SizedBox(height: 8),
        TextField(controller: _dp, decoration: const InputDecoration(labelText: 'Số công tắc (DP)', helperText: 'Hầu hết ổ cắm dùng 1')),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: FilledButton.tonalIcon(onPressed: _busy ? null : () => _try(true), icon: const Icon(Icons.power), label: const Text('Thử BẬT'))),
          const SizedBox(width: 12),
          Expanded(child: FilledButton.tonalIcon(onPressed: _busy ? null : () => _try(false), icon: const Icon(Icons.power_off), label: const Text('Thử TẮT'))),
        ]),
        if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
        if (_log.isNotEmpty || _result != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: SelectableText([..._log, if (_result != null) '', if (_result != null) '${_ok == true ? '✓' : '✗'} $_result'].join('\n'), style: const TextStyle(fontSize: 13)),
          ),
        const Divider(height: 32),
        Row(children: [
          Expanded(child: Text('Hẹn giờ bật / tắt', style: text.titleMedium)),
          TextButton.icon(onPressed: () => _editRule(), icon: const Icon(Icons.add), label: const Text('Thêm giờ')),
        ]),
        const Text(
          'Đến giờ, app tự bật hoặc tắt thiết bị này (kể cả khi app đang đóng). Ví dụ: BẬT lúc 06:29, TẮT lúc 07:15. '
          'Đặt giờ BẬT sớm hơn báo thức khoảng nửa phút để loa kịp khởi động.',
          style: TextStyle(fontSize: 12),
        ),
        ValueListenableBuilder<TuyaData>(
          valueListenable: widget.hub.data,
          builder: (_, data, _) {
            final rules = [...data.rulesOf(_id)]..sort((a, b) => a.time.totalMinutes.compareTo(b.time.totalMinutes));
            if (rules.isEmpty) return const Padding(padding: EdgeInsets.all(12), child: Text('Chưa có hẹn giờ nào.'));
            return Column(children: [
              for (final r in rules)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(r.on ? Icons.power : Icons.power_off),
                  title: Text(ruleLabel(r)),
                  onTap: () => _editRule(r),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Switch(value: r.enabled, onChanged: (v) => widget.hub.upsertRule(r.copyWith(enabled: v))),
                    IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Xóa giờ này', onPressed: () => widget.hub.removeRule(r.id)),
                  ]),
                ),
            ]);
          },
        ),
      ]),
    );
  }
}

/// Pick on or off, the time, and the days of one timer.
class _RuleDialog extends StatefulWidget {
  final TuyaRule rule;
  const _RuleDialog({required this.rule});

  @override
  State<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<_RuleDialog> {
  late TuyaRule _r = widget.rule;

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: _r.time.hour, minute: _r.time.minute));
    if (t != null) setState(() => _r = _r.copyWith(time: TimeOfDayMin(t.hour, t.minute)));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Hẹn giờ'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, icon: Icon(Icons.power), label: Text('BẬT')),
              ButtonSegment(value: false, icon: Icon(Icons.power_off), label: Text('TẮT')),
            ],
            selected: {_r.on},
            onSelectionChanged: (s) => setState(() => _r = _r.copyWith(on: s.first)),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: _pickTime,
              child: Text(timeLabel(_r.time), style: Theme.of(context).textTheme.displaySmall),
            ),
          ),
          Wrap(spacing: 6, children: [
            for (final d in weekdayShort.entries)
              FilterChip(
                label: Text(d.value),
                selected: _r.weekdays.contains(d.key),
                onSelected: (on) => setState(() {
                  final days = {..._r.weekdays};
                  on ? days.add(d.key) : days.remove(d.key);
                  _r = _r.copyWith(weekdays: days);
                }),
              ),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
        FilledButton(onPressed: _r.weekdays.isEmpty ? null : () => Navigator.pop(context, _r), child: const Text('Lưu')),
      ],
    );
  }
}
