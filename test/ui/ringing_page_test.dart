import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_timer_player/ui/ringing_page.dart';

void main() {
  testWidgets('shows the alarm name and a stop button that calls onStop', (t) async {
    var stopped = 0;
    final alarm = AlarmSettings(
      id: 7,
      dateTime: DateTime(2026, 11, 3, 6, 30),
      volumeSettings: VolumeSettings.fixed(volume: 0.5),
      notificationSettings: const NotificationSettings(title: 'Dậy đi', body: 'Dậy thôi!'),
    );
    await t.pumpWidget(MaterialApp(home: RingingPage(alarm: alarm, onStop: () => stopped++)));
    expect(find.text('Dậy đi'), findsOneWidget);
    await t.tap(find.text('TẮT'));
    expect(stopped, 1);
  });
}
