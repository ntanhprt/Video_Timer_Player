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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${_two(_now.hour)}:${_two(_now.minute)}:${_two(_now.second)}',
                  key: const Key('clock'),
                  style: text.displayLarge?.copyWith(
                    color: on,
                    fontWeight: FontWeight.bold,
                    fontSize: 84,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Text(
                '${_days[_now.weekday - 1]}, ${_two(_now.day)}/${_two(_now.month)}/${_now.year}',
                textAlign: TextAlign.center,
                style: text.titleLarge?.copyWith(color: on),
              ),
              const SizedBox(height: 24),
              Text(widget.alarm.notificationSettings.title, textAlign: TextAlign.center, style: text.headlineMedium?.copyWith(color: on)),
              const SizedBox(height: 4),
              Text(widget.alarm.notificationSettings.body, textAlign: TextAlign.center, style: text.titleMedium?.copyWith(color: on)),
              const SizedBox(height: 24),
              SizedBox(
                height: 96,
                child: FilledButton(
                  onPressed: widget.onStop,
                  child: const Text('TẮT', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 24),
              Text('Báo lại sau', textAlign: TextAlign.center, style: text.titleMedium?.copyWith(color: on)),
              const SizedBox(height: 8),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.8,
                children: [
                  for (final c in snoozeChoices)
                    FilledButton.tonal(
                      onPressed: () => widget.onSnooze(Duration(minutes: c.minutes)),
                      child: Text(c.label, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
            ],
          ),
        ),
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
