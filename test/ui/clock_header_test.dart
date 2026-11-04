import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_timer_player/ui/clock_header.dart';

void main() {
  test('formats time and date in Vietnamese', () {
    final t = DateTime(2026, 11, 4, 5, 7, 9);
    expect(clockText(t), '05:07:09');
    expect(dateText(t), 'Thứ Tư, 04/11/2026');
    expect(dateText(DateTime(2026, 11, 8)), 'Chủ Nhật, 08/11/2026');
  });

  testWidgets('shows the current time and follows the clock', (tester) async {
    var now = DateTime(2026, 11, 4, 5, 59, 58);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ClockHeader(now: () => now))));
    expect(find.text('05:59:58'), findsOneWidget);
    expect(find.text('Thứ Tư, 04/11/2026'), findsOneWidget);
    now = DateTime(2026, 11, 4, 6, 0, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('06:00:01'), findsOneWidget);
  });
}
