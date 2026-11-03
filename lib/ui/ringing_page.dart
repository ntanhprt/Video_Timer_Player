import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:flutter/material.dart';

import '../alarm/plan.dart';

const snoozeChoices = [
  (label: '5 phút', minutes: 5),
  (label: '10 phút', minutes: 10),
  (label: '15 phút', minutes: 15),
  (label: '20 phút', minutes: 20),
  (label: '30 phút', minutes: 30),
  (label: '1 giờ', minutes: 60),
];

String _two(int n) => n.toString().padLeft(2, '0');

/// Full-screen "alarm is ringing" view: a live clock, one big stop button and quick snooze buttons.
class RingingPage extends StatefulWidget {
  final AlarmSettings alarm;
  final VoidCallback onStop;
  final void Function(Duration) onSnooze;
  final DateTime Function()? clock;
  const RingingPage({super.key, required this.alarm, required this.onStop, required this.onSnooze, this.clock});

  @override
  State<RingingPage> createState() => _RingingPageState();
}

class _RingingPageState extends State<RingingPage> {
  late DateTime _now = _read();

  DateTime _read() => (widget.clock ?? DateTime.now)();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _now = _read()));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  static const _days = ['Thứ hai', 'Thứ ba', 'Thứ tư', 'Thứ năm', 'Thứ sáu', 'Thứ bảy', 'Chủ nhật'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final on = scheme.onPrimaryContainer;
    final text = Theme.of(context).textTheme;
    return Material(
      color: scheme.primaryContainer,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${_two(_now.hour)}:${_two(_now.minute)}:${_two(_now.second)}',
                        key: const Key('clock'),
                        style: text.displayLarge?.copyWith(color: on, fontWeight: FontWeight.bold, fontSize: 88, fontFeatures: const [FontFeature.tabularFigures()]),
                      ),
                      Text(
                        '${_days[_now.weekday - 1]}, ${_two(_now.day)}/${_two(_now.month)}/${_now.year}  •  ${widget.alarm.notificationSettings.title}',
                        style: text.titleMedium?.copyWith(color: on),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // One huge stop button: easy to hit half asleep.
              Expanded(
                flex: 5,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  ),
                  onPressed: widget.onStop,
                  child: const FittedBox(child: Padding(padding: EdgeInsets.all(8), child: Text('TẮT', style: TextStyle(fontSize: 96, fontWeight: FontWeight.w900)))),
                ),
              ),
              const SizedBox(height: 12),
              Text('BÁO LẠI SAU', textAlign: TextAlign.center, style: text.titleMedium?.copyWith(color: on, fontWeight: FontWeight.bold, letterSpacing: 2)),
              const SizedBox(height: 6),
              // 2 columns x 3 rows of big blocks filling the rest of the screen.
              Expanded(
                flex: 7,
                child: Column(
                  children: [
                    for (var row = 0; row < 3; row++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(bottom: row < 2 ? 10 : 0),
                          child: Row(
                            children: [
                              for (var col = 0; col < 2; col++) ...[
                                if (col == 1) const SizedBox(width: 10),
                                Expanded(child: _snoozeButton(snoozeChoices[row * 2 + col], scheme)),
                              ],
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _snoozeButton(({String label, int minutes}) c, ColorScheme scheme) {
    return SizedBox.expand(
      child: FilledButton.tonal(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.secondary,
          foregroundColor: scheme.onSecondary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        ),
        onPressed: () => widget.onSnooze(Duration(minutes: c.minutes)),
        child: FittedBox(child: Padding(padding: const EdgeInsets.all(6), child: Text(c.label, style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800)))),
      ),
    );
  }
}

/// Stops the ringing alarm and rings it again in [delay], with the same sound and volume ramp.
Future<void> snooze(AlarmSettings ringing, Duration delay) async {
  await Alarm.stop(ringing.id);
  await Alarm.set(alarmSettings: ringing.copyWith(id: snoozeAlarmId, dateTime: DateTime.now().add(delay)));
}

/// Shows [RingingPage] over [child] whenever an alarm is ringing.
class RingingOverlay extends StatelessWidget {
  final Widget child;
  const RingingOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AlarmSet>(
      stream: Alarm.ringing,
      initialData: Alarm.ringing.value,
      builder: (context, snap) {
        final ringing = snap.data?.alarms ?? const <AlarmSettings>{};
        return Stack(
          children: [
            child,
            if (ringing.isNotEmpty)
              Positioned.fill(
                child: RingingPage(
                  alarm: ringing.first,
                  onStop: () => Alarm.stop(ringing.first.id),
                  onSnooze: (d) => snooze(ringing.first, d),
                ),
              ),
          ],
        );
      },
    );
  }
}
