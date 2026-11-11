import 'package:flutter/material.dart';

import '../alarm/music_library.dart';

String sizeLabel(int bytes) => '${(bytes / 1048576).toStringAsFixed(1)} MB';

/// Lists every audio file on the phone and lets the user tick several to add to an alarm.
/// Pops with the ticked tracks.
class LibrarySheet extends StatefulWidget {
  final List<LibraryTrack> tracks;

  /// Whether the alarm being edited already plays this track.
  final bool Function(LibraryTrack) alreadyIn;
  const LibrarySheet({super.key, required this.tracks, required this.alreadyIn});

  @override
  State<LibrarySheet> createState() => _LibrarySheetState();
}

class _LibrarySheetState extends State<LibrarySheet> {
  final _picked = <String>{};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tracks = widget.tracks;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Nhạc đã có trong máy (${tracks.length} bài)', style: theme.textTheme.titleMedium),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Gồm nhạc YouTube đã tải và file đã chọn ở mọi báo thức. Tích những bài muốn thêm vào báo thức này.', style: TextStyle(fontSize: 12)),
            ),
          ),
          if (tracks.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Text('Chưa có bài nào trong máy. Hãy tải link YouTube hoặc chọn file nhạc trước.'))
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: tracks.length,
                itemBuilder: (_, i) {
                  final t = tracks[i];
                  final already = widget.alreadyIn(t);
                  return CheckboxListTile(
                    key: Key('lib-${t.path}'),
                    dense: true,
                    secondary: Icon(t.youtube ? Icons.smart_display : Icons.audio_file),
                    title: Text(t.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${t.youtube ? 'YouTube' : 'File trong máy'} • ${sizeLabel(t.bytes)}${already ? ' • đã có trong danh sách' : ''}'),
                    value: already || _picked.contains(t.path),
                    onChanged: already
                        ? null
                        : (on) => setState(() {
                              on == true ? _picked.add(t.path) : _picked.remove(t.path);
                            }),
                  );
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('library-add'),
                onPressed: _picked.isEmpty ? null : () => Navigator.of(context).pop([for (final t in tracks) if (_picked.contains(t.path)) t]),
                icon: const Icon(Icons.playlist_add),
                label: Text(_picked.isEmpty ? 'Chọn bài để thêm' : 'Thêm ${_picked.length} bài'),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
