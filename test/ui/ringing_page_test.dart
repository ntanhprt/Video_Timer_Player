import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_timer_player/ui/ringing_page.dart';

void main() {
  final alarm = AlarmSettings(
    id: 7,
    dateTime: DateTime(2026, 11, 3, 6, 30),
    volumeSettings: VolumeSettings.fixed(volume: 0.5),
    notificationSettings: const NotificationSettings(title: 'Dậy đi', body: 'Dậy thôi!'),
  );

  Future<void> pump(WidgetTester t, {VoidCallback? onStop, void Function(Duration)? onSnooze}) => t.pumpWidget(MaterialApp(
        home: RingingPage(
          alarm: alarm,
          onStop: onStop ?? () {},
          onSnooze: onSnooze ?? (_) {},
          clock: () => DateTime(2026, 11, 3, 6, 30, 5),
        ),
      ));

  testWidgets('shows the alarm name and a stop button that calls onStop', (t) async {
    var stopped = 0;
    await pump(t, onStop: () => stopped++);
    expect(find.text('Dậy đi'), findsOneWidget);
    await t.tap(find.text('TẮT'));
    expect(stopped, 1);
  });

  testWidgets('shows the current time and date', (t) async {
    await pump(t);
    expect(find.text('06:30:05'), findsOneWidget);
    expect(find.textContaining('03/11/2026'), findsOneWidget);
  });

  testWidgets('has snooze buttons for 5, 10, 15, 20, 30 minutes and 1 hour', (t) async {
    final got = <Duration>[];
    await pump(t, onSnooze: got.add);
    for (final label in ['5 phút', '10 phút', '15 phút', '20 phút', '30 phút', '1 giờ']) {
      await t.ensureVisible(find.text(label));
      await t.tap(find.text(label));
    }
    expect(got, [for (final m in [5, 10, 15, 20, 30, 60]) Duration(minutes: m)]);
  });
}
