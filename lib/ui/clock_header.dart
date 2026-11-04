import 'dart:async';

import 'package:flutter/material.dart';

const _weekdays = {1: 'Thứ Hai', 2: 'Thứ Ba', 3: 'Thứ Tư', 4: 'Thứ Năm', 5: 'Thứ Sáu', 6: 'Thứ Bảy', 7: 'Chủ Nhật'};

String _two(int n) => n.toString().padLeft(2, '0');

String clockText(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

String dateText(DateTime t) => '${_weekdays[t.weekday]}, ${_two(t.day)}/${_two(t.month)}/${t.year}';

/// The current time, big, at the top of the main screen (the clock keeps running after the alarm is
/// switched off, so the user can see the time without leaving the app).
class ClockHeader extends StatefulWidget {
  final DateTime Function() now;
  const ClockHeader({super.key, this.now = DateTime.now});

  @override
  State<ClockHeader> createState() => _ClockHeaderState();
}

class _ClockHeaderState extends State<ClockHeader> {
  Timer? _timer;
  late DateTime _t = widget.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final n = widget.now();
      if (n.second != _t.second || n.minute != _t.minute) setState(() => _t = n);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(children: [
        Text(
          clockText(_t),
          key: const Key('clock'),
          style: theme.textTheme.displayMedium?.copyWith(fontWeight: FontWeight.bold, fontFeatures: const [FontFeature.tabularFigures()]),
        ),
        Text(dateText(_t), key: const Key('clockDate'), style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ]),
    );
  }
}
