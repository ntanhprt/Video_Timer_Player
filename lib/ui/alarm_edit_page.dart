import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import '../core/alarm.dart';
import '../core/schedule.dart';
import '../core/validation.dart';
import '../core/volume_curve.dart';
import '../data/alarm_repository.dart';
import 'curve_preview.dart';

const _dayNames = {1: 'T2', 2: 'T3', 3: 'T4', 4: 'T5', 5: 'T6', 6: 'T7', 7: 'CN'};

String outputLabel(OutputKind o) => switch (o) {
      OutputKind.speaker => 'Loa điện thoại',
      OutputKind.bluetooth => 'Loa Bluetooth',
      OutputKind.wired => 'Loa cắm dây',
      OutputKind.anyConnected => 'Loa đang kết nối',
    };

/// Links pasted one per line (or separated by spaces/commas); blanks and repeats dropped.
List<String> parseLinks(String text) => {
      for (final u in text.split(RegExp(r'[\s,]+'))) if (u.trim().isNotEmpty) u.trim(),
    }.toList();

String _newId() => '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${Random().nextInt(1 << 20).toRadixString(36)}';

/// Create (initial == null) or edit an alarm.
///
/// Only weekly schedules can be edited here for now; other kinds keep their schedule untouched.
class AlarmEditPage extends StatefulWidget {
  final AlarmRepository repo;
  final Alarm? initial;

  /// Rings the alarm shortly so it can be tried now; returns a message for the user.
  final Future<String> Function(Alarm alarm)? onTest;
  const AlarmEditPage({super.key, required this.repo, this.initial, this.onTest});

  @override
  State<AlarmEditPage> createState() => _AlarmEditPageState();
}

class _AlarmEditPageState extends State<AlarmEditPage> {
  late final TextEditingController _name;
  late final TextEditingController _url;
  late ScheduleSpec _schedule;
  late VolumeSpec _volume;
  late OutputKind _output;
  List<String> _errors = const [];

  /// What the form looked like when it was opened or last saved, to tell unsaved edits.
  late String _baseline;

  String _snapshot() => jsonEncode([_name.text, parseLinks(_url.text), _schedule.toJson(), _volume.toJson(), _output.name]);
  bool get _dirty => _snapshot() != _baseline;

  @override
  void initState() {
    super.initState();
    final a = widget.initial;
    _name = TextEditingController(text: a?.name ?? 'Báo thức');
    _url = TextEditingController(text: (a?.youtubeUrls ?? const <String>[]).join('\n'));
    _schedule = a?.schedule ?? const Weekly(TimeOfDayMin(6, 30), {1, 2, 3, 4, 5});
    _volume = a?.volume ?? const VolumeSpec();
    _output = a?.output ?? OutputKind.anyConnected;
    _baseline = _snapshot();
    _name.addListener(_refresh);
    _url.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  Alarm _build() {
    final a = widget.initial;
    return Alarm(
      id: a?.id ?? _newId(),
      name: _name.text.trim().isEmpty ? 'Báo thức' : _name.text.trim(),
      schedule: _schedule,
      youtubeUrls: parseLinks(_url.text),
      volume: _volume,
      output: _output,
      fallbackPath: a?.fallbackPath,
      enabled: a?.enabled ?? true,
      rev: a?.rev ?? 0,
      updatedAt: a?.updatedAt ?? DateTime.now(),
    );
  }

  Future<void> _save() async {
    final alarm = _build();
    final errors = validate(alarm);
    setState(() => _errors = errors);
    if (errors.isNotEmpty) return;
    await widget.repo.upsert(alarm);
    if (!mounted) return;
    setState(() => _baseline = _snapshot());
    Navigator.of(context).maybePop();
  }

  Future<void> _test() async {
    final alarm = _build();
    final errors = validate(alarm);
    setState(() => _errors = errors);
    if (errors.isNotEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Đang chuẩn bị... (tải nhạc có thể mất vài chục giây)')));
    final msg = await widget.onTest!(alarm);
    messenger.hideCurrentSnackBar();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thử báo thức'),
        content: SingleChildScrollView(child: SelectableText('$msg\n\nKhóa màn hình để thử.')),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Đóng'))],
      ),
    );
  }

  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chưa lưu'),
        content: const Text('Các thay đổi (kể cả link YouTube vừa dán) chưa được lưu. Thoát sẽ mất.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Ở lại')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Thoát, bỏ thay đổi')),
        ],
      ),
    );
    if (leave == true && mounted) {
      setState(() => _baseline = _snapshot());
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _delete() async {
    final a = widget.initial;
    if (a == null) return;
    await widget.repo.softDelete(a.id);
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _pickTime(Weekly w) async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: w.time.hour, minute: w.time.minute));
    if (t != null) setState(() => _schedule = Weekly(TimeOfDayMin(t.hour, t.minute), w.weekdays));
  }

  String _pct(double v) => '${(v * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    final schedule = _schedule;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text('${widget.initial == null ? 'Báo thức mới' : 'Sửa báo thức'}${_dirty ? ' • chưa lưu' : ''}'),
        actions: [
          if (widget.initial != null) IconButton(tooltip: 'Xóa', icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('Lưu'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_errors.isNotEmpty)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [for (final e in _errors) Text(e)],
                ),
              ),
            ),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Tên')),
          const SizedBox(height: 12),
          TextField(
            key: const Key('youtubeUrl'),
            controller: _url,
            keyboardType: TextInputType.multiline,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Liên kết YouTube (mỗi dòng một bài)',
              helperText: 'Mỗi lần kêu phát ngẫu nhiên một bài. Để trống: phát nhạc dự phòng',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          if (schedule is Weekly) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Giờ báo'),
              trailing: TextButton(
                onPressed: () => _pickTime(schedule),
                child: Text(
                  '${schedule.time.hour.toString().padLeft(2, '0')}:${schedule.time.minute.toString().padLeft(2, '0')}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            ),
            Wrap(
              spacing: 6,
              children: [
                for (final d in _dayNames.entries)
                  FilterChip(
                    label: Text(d.value),
                    selected: schedule.weekdays.contains(d.key),
                    onSelected: (on) => setState(() {
                      final days = {...schedule.weekdays};
                      on ? days.add(d.key) : days.remove(d.key);
                      _schedule = Weekly(schedule.time, days);
                    }),
                  ),
              ],
            ),
          ] else
            const ListTile(contentPadding: EdgeInsets.zero, title: Text('Loại hẹn này chưa chỉnh được trên màn hình này')),
          const Divider(height: 32),
          Text('Âm lượng', style: Theme.of(context).textTheme.titleMedium),
          _slider('Bắt đầu', _volume.start, 0, 1, 100, _pct(_volume.start), (v) => _setVolume(start: v)),
          _slider('Đích', _volume.target, 0, 1, 100, _pct(_volume.target), (v) => _setVolume(target: v)),
          _slider('Thời gian tăng', _volume.ramp.inSeconds.toDouble(), 0, 300, 60, '${_volume.ramp.inSeconds} giây',
              (v) => _setVolume(ramp: Duration(seconds: v.round()))),
          _slider('Phát tối đa', _volume.hold.inMinutes.toDouble().clamp(1, 120), 1, 120, 119, '${_volume.hold.inMinutes} phút',
              (v) => _setVolume(hold: Duration(minutes: v.round()))),
          const SizedBox(height: 8),
          SegmentedButton<RampCurve>(
            segments: const [
              ButtonSegment(value: RampCurve.linear, label: Text('Đều')),
              ButtonSegment(value: RampCurve.easeIn, label: Text('Êm đầu')),
              ButtonSegment(value: RampCurve.easeOut, label: Text('Nhanh đầu')),
            ],
            selected: {_volume.curve},
            onSelectionChanged: (s) => _setVolume(curve: s.first),
          ),
          const SizedBox(height: 12),
          CurvePreview(spec: _volume),
          const Divider(height: 32),
          DropdownButtonFormField<OutputKind>(
            initialValue: _output,
            decoration: const InputDecoration(labelText: 'Phát ra'),
            items: [for (final o in OutputKind.values) DropdownMenuItem(value: o, child: Text(outputLabel(o)))],
            onChanged: (o) => setState(() => _output = o ?? _output),
          ),
          if (widget.onTest != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _test,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Thử ngay (kêu sau 10 giây)'),
            ),
          ],
        ],
      ),
    ),
    );
  }

  void _setVolume({double? start, double? target, Duration? ramp, Duration? hold, RampCurve? curve}) {
    setState(() {
      _volume = VolumeSpec(
        start: start ?? _volume.start,
        target: target ?? _volume.target,
        ramp: ramp ?? _volume.ramp,
        hold: hold ?? _volume.hold,
        curve: curve ?? _volume.curve,
      );
    });
  }

  Widget _slider(String label, double value, double min, double max, int divisions, String shown, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 110, child: Text(label)),
        Expanded(child: Slider(value: value.clamp(min, max), min: min, max: max, divisions: divisions, onChanged: onChanged)),
        SizedBox(width: 64, child: Text(shown, textAlign: TextAlign.end)),
      ],
    );
  }
}
