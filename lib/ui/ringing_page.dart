import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:flutter/material.dart';

/// Full-screen "alarm is ringing" view with one big stop button.
class RingingPage extends StatelessWidget {
  final AlarmSettings alarm;
  final VoidCallback onStop;
  const RingingPage({super.key, required this.alarm, required this.onStop});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.alarm_on, size: 96, color: scheme.onPrimaryContainer),
              const SizedBox(height: 16),
              Text(
                alarm.notificationSettings.title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(color: scheme.onPrimaryContainer),
              ),
              const SizedBox(height: 8),
              Text(
                alarm.notificationSettings.body,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(color: scheme.onPrimaryContainer),
              ),
              const SizedBox(height: 64),
              SizedBox(
                height: 96,
                child: FilledButton(
                  onPressed: onStop,
                  child: const Text('TẮT', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
                child: RingingPage(alarm: ringing.first, onStop: () => Alarm.stop(ringing.first.id)),
              ),
          ],
        );
      },
    );
  }
}
