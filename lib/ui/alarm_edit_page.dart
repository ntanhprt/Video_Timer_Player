import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../alarm/music_library.dart';
import '../core/alarm.dart';
import '../core/schedule.dart';
import '../core/validation.dart';
import '../core/volume_curve.dart';
import '../data/alarm_repository.dart';
import 'curve_preview.dart';
import 'library_sheet.dart';

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
  final Future<String> Function(Alarm alarm, void Function(String) log)? onTest;
  /// Downloads the given links now, reporting steps to the log; returns a summary.
  final Future<String> Function(List<String> urls, void Function(String) log)? onDownload;
  /// Path of the downloaded audio for a link, or null when it is not on the phone yet.
  final Future<String?> Function(String url)? cachedPath;

  /// Title of the video behind a link, once downloaded.
  final Future<String?> Function(String url)? titleOf;

  /// Every audio file on the phone, whichever alarm it came from, to choose into this alarm.
  final Future<List<LibraryTrack>> Function()? onLibrary;
  const AlarmEditPage({super.key, required this.repo, this.initial, this.onTest, this.onDownload, this.cachedPath, this.titleOf, this.onLibrary});

  @override
  State<AlarmEditPage> createState() => _AlarmEditPageState();
}

class _AlarmEditPageState extends State<AlarmEditPage> {
  late final TextEditingController _name;
  late final TextEditingController _url;
  late ScheduleSpec _schedule;
  late VolumeSpec _volume;
  late OutputKind _output;
  late List<String> _files;
  late bool _random;

  AudioPlayer? _player; // created on first preview
  String? _playing; // key of the track being previewed
  final _cachedFutures = <String, Future<({String? path, String? title})>>{};
  List<String> _errors = const [];

  /// What the form looked like when it was opened or last saved, to tell unsaved edits.
  late String _baseline;

  String _snapshot() => jsonEncode([_name.text, parseLinks(_url.text), _files, _random, _schedule.toJson(), _volume.toJson(), _output.name]);
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
    _files = [...?a?.audioFiles];
    _random = a?.randomOrder ?? true;
    _baseline = _snapshot();
    _name.addListener(_refresh);
    _url.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _player?.dispose();
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
      audioFiles: _files,
      randomOrder: _random,
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
    _closeAfterRebuild();
  }

  /// Closes the page without the "unsaved changes" question.
  ///
  /// `canPop` is only read when the page rebuilds, so mark everything as saved first and pop on the
  /// next frame; popping right away still sees the old unsaved state and asks.
  void _closeAfterRebuild() {
    setState(() => _baseline = _snapshot());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  /// Shows a dialog that fills with the steps of [task] as it runs.
  Future<void> _runWithLog(String title, Future<String> Function(void Function(String) log) task) async {
    final lines = ValueNotifier<List<String>>([]);
    final done = ValueNotifier<bool>(false);
    void log(String m) {
      final t = DateTime.now();
      final stamp = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
      lines.value = [...lines.value, '$stamp  $m'];
    }

    final dialog = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: ValueListenableBuilder<List<String>>(
            valueListenable: lines,
            builder: (_, l, _) => ListView(
              shrinkWrap: true,
              children: [
                for (final m in l.length > 40 ? l.sublist(l.length - 40) : l) SelectableText(m, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ),
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: done,
            builder: (_, d, _) => TextButton(onPressed: d ? () => Navigator.of(ctx).pop() : null, child: Text(d ? 'Đóng' : 'Đang chạy...')),
          ),
        ],
      ),
    );
    log('Bắt đầu.');
    try {
      log('Kết quả: ${await task(log)}');
    } catch (e) {
      log('LỖI: $e');
    }
    done.value = true;
    await dialog;
  }

  Future<void> _test() async {
    final alarm = _build();
    final errors = validate(alarm);
    setState(() => _errors = errors);
    if (errors.isNotEmpty) return;
    await _runWithLog('Thử báo thức', (log) => widget.onTest!(alarm, log));
  }

  Future<void> _downloadNow() async {
    final urls = parseLinks(_url.text);
    final bad = validate(_build());
    setState(() => _errors = bad);
    if (bad.isNotEmpty) return;
    await _runWithLog('Tải nhạc YouTube', (log) => widget.onDownload!(urls, log));
    if (mounted) setState(_cachedFutures.clear);
  }

  Future<({String? path, String? title})> _infoOf(String url) => _cachedFutures.putIfAbsent(url, () async {
        final path = await widget.cachedPath?.call(url);
        final title = path == null ? null : await widget.titleOf?.call(url);
        return (path: path, title: title);
      });

  Future<void> _preview(String key, String path) async {
    final player = _player ??= AudioPlayer()..onPlayerComplete.listen((_) => setState(() => _playing = null));
    if (_playing == key) {
      await player.stop();
      setState(() => _playing = null);
      return;
    }
    try {
      await player.stop();
      await player.play(DeviceFileSource(path));
      setState(() => _playing = key);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Không phát thử được: $e')));
    }
  }

  void _removeLink(String url) {
    final rest = parseLinks(_url.text)..remove(url);
    _url.text = rest.join('\n');
    if (_playing == url) {
      _player?.stop();
      _playing = null;
    }
  }

  void _removeFile(String f) {
    setState(() => _files = [..._files]..remove(f));
    if (_playing == f) {
      _player?.stop();
      _playing = null;
    }
  }

  Widget _trackTile({required IconData icon, required String title, required String status, required String? playPath, required String key, VoidCallback? onDownload, required VoidCallback onRemove}) {
    final playing = _playing == key;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(icon),
      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(status),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (playPath != null)
          IconButton(tooltip: playing ? 'Dừng' : 'Nghe thử', icon: Icon(playing ? Icons.stop_circle : Icons.play_circle), onPressed: () => _preview(key, playPath))
        else if (onDownload != null)
          IconButton(tooltip: 'Tải bài này', icon: const Icon(Icons.download), onPressed: onDownload),
        IconButton(tooltip: 'Loại khỏi danh sách', icon: const Icon(Icons.delete_outline), onPressed: onRemove),
      ]),
    );
  }

  String _size(String path) {
    try {
      return '${(File(path).lengthSync() / 1048576).toStringAsFixed(1)} MB';
    } catch (_) {
      return '';
    }
  }

  Widget _trackList() {
    final urls = parseLinks(_url.text);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Danh sách nhạc báo thức (${urls.length + _files.length} bài)', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 4),
      SegmentedButton<bool>(
        key: const Key('playOrder'),
        segments: const [
          ButtonSegment(value: true, icon: Icon(Icons.shuffle), label: Text('Ngẫu nhiên')),
          ButtonSegment(value: false, icon: Icon(Icons.format_list_numbered), label: Text('Theo thứ tự')),
        ],
        selected: {_random},
        onSelectionChanged: (s) => setState(() => _random = s.first),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          _random
              ? 'Mỗi lần kêu bốc ngẫu nhiên một bài trong nhóm "Sẽ phát".'
              : 'Mỗi ngày phát một bài theo đúng thứ tự trong nhóm "Sẽ phát", hết thì quay lại bài đầu.',
          style: const TextStyle(fontSize: 12),
        ),
      ),
      FutureBuilder<List<({String url, String? path, String? title})>>(
        // Rebuilt whenever the form changes; the per-link futures are cached.
        future: Future.wait([for (final u in urls) _infoOf(u).then((i) => (url: u, path: i.path, title: i.title))]),
        builder: (_, snap) {
          final infos = snap.data;
          if (infos == null) return const Padding(padding: EdgeInsets.all(8), child: Text('Đang kiểm tra...'));
          final ready = [for (final i in infos) if (i.path != null) i];
          final pending = [for (final i in infos) if (i.path == null) i];
          final existing = [for (final f in _files) if (File(f).existsSync()) f];
          final missingFiles = [for (final f in _files) if (!File(f).existsSync()) f];
          var n = 0;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _groupHeader('Sẽ phát (${ready.length + existing.length} bài, đã có trong máy)'),
            if (ready.isEmpty && existing.isEmpty)
              const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('Chưa có bài nào sẵn sàng: sẽ phát nhạc dự phòng của app.')),
            for (final i in ready)
              _trackTile(
                icon: Icons.smart_display,
                title: '${_random ? '' : '${++n}. '}${i.title ?? i.url}',
                status: 'YouTube • đã tải ${_size(i.path!)}${i.title == null ? '' : '\n${i.url}'}',
                playPath: i.path,
                key: i.url,
                onRemove: () => _removeLink(i.url),
              ),
            for (final f in existing)
              _trackTile(
                icon: Icons.audio_file,
                title: '${_random ? '' : '${++n}. '}${p.basename(f).replaceFirst(RegExp(r'^\d+_'), '')}',
                status: 'File trong máy • ${_size(f)}',
                playPath: f,
                key: f,
                onRemove: () => _removeFile(f),
              ),
            if (pending.isNotEmpty || missingFiles.isNotEmpty) _groupHeader('Chưa tải / không dùng được (${pending.length + missingFiles.length})'),
            for (final i in pending)
              _trackTile(
                icon: Icons.cloud_download,
                title: i.url,
                status: 'YouTube • CHƯA TẢI — bấm nút tải để lấy về máy (chưa được phát)',
                playPath: null,
                key: i.url,
                onDownload: widget.onDownload == null
                    ? null
                    : () async {
                        await _runWithLog('Tải bài này', (log) => widget.onDownload!([i.url], log));
                        if (mounted) setState(() => _cachedFutures.remove(i.url));
                      },
                onRemove: () => _removeLink(i.url),
              ),
            for (final f in missingFiles)
              _trackTile(
                icon: Icons.error_outline,
                title: p.basename(f).replaceFirst(RegExp(r'^\d+_'), ''),
                status: 'File không còn tồn tại',
                playPath: null,
                key: f,
                onRemove: () => _removeFile(f),
              ),
          ]);
        },
      ),
    ]);
  }

  /// Opens the list of every audio file on the phone and adds the ticked ones to this alarm.
  Future<void> _addFromLibrary() async {
    final all = await widget.onLibrary!();
    if (!mounted) return;
    final links = parseLinks(_url.text);
    bool inList(LibraryTrack t) => (t.url != null && links.contains(t.url)) || _files.contains(t.path);
    final picked = await showModalBottomSheet<List<LibraryTrack>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => LibrarySheet(tracks: all, alreadyIn: inList),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    final urls = [...links];
    final files = [..._files];
    for (final t in picked) {
      final u = t.url;
      if (u != null) {
        if (!urls.contains(u)) urls.add(u);
        _cachedFutures.remove(u);
      } else if (!files.contains(t.path)) {
        files.add(t.path);
      }
    }
    setState(() => _files = files);
    _url.text = urls.join('\n');
  }

  Widget _groupHeader(String text) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(text, style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
      );

  Future<void> _pickFiles() async {
    final picked = await FilePicker.pickFiles(type: FileType.audio);
    if (picked.isEmpty) return;
    final dir = await musicDirectory();
    final added = <String>[];
    for (final f in picked) {
      final src = f.path;
      if (src == null) continue;
      // Copy so the alarm still works if the original is moved or the picker cache is cleared.
      final dest = File(p.join(dir.path, '${DateTime.now().microsecondsSinceEpoch}_${p.basename(src)}'));
      await File(src).copy(dest.path);
      added.add(dest.path);
    }
    if (mounted) setState(() => _files = [..._files, ...added]);
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
    if (leave == true && mounted) _closeAfterRebuild();
  }

  Future<void> _delete() async {
    final a = widget.initial;
    if (a == null) return;
    await widget.repo.softDelete(a.id);
    if (mounted) _closeAfterRebuild();
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
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              key: const Key('save'),
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('Lưu'),
            ),
          ),
        ],
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
          if (widget.onDownload != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('downloadNow'),
                onPressed: _downloadNow,
                icon: const Icon(Icons.download),
                label: const Text('Tải ngay'),
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('pickFiles'),
            onPressed: _pickFiles,
            icon: const Icon(Icons.folder_open),
            label: const Text('Chọn file nhạc trong máy (nhiều file)'),
          ),
          if (widget.onLibrary != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                key: const Key('pickFromLibrary'),
                onPressed: _addFromLibrary,
                icon: const Icon(Icons.library_music),
                label: const Text('Chọn từ nhạc đã tải / đã có trong máy'),
              ),
            ),
          const SizedBox(height: 12),
          _trackList(),
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
