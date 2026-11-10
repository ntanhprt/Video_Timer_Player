import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_timer_player/alarm/alarm_health.dart';
import 'package:video_timer_player/ui/health_banner.dart';

void main() {
  Widget host(ValueNotifier<AlarmHealth> h, {VoidCallback? onSettings, VoidCallback? onDismiss}) => MaterialApp(
        home: Scaffold(body: HealthBanner(health: h, onOpenSettings: onSettings ?? () {}, onDismissWiped: onDismiss ?? () {})),
      );

  testWidgets('shows nothing when all is well', (tester) async {
    await tester.pumpWidget(host(ValueNotifier(AlarmHealth.ok)));
    expect(find.byKey(const Key('health-banner')), findsNothing);
  });

  testWidgets('a wipe is a loud warning that can be dismissed', (tester) async {
    final h = ValueNotifier(const AlarmHealth({AlarmProblem.wiped}));
    var dismissed = 0;
    await tester.pumpWidget(host(h, onDismiss: () {
      dismissed++;
      h.value = h.value.without(AlarmProblem.wiped);
    }));
    expect(find.text('Báo thức có thể đã bị lỡ'), findsOneWidget);
    expect(find.textContaining('Hệ thống đã xóa báo thức'), findsOneWidget);
    await tester.tap(find.byKey(const Key('health-dismiss')));
    await tester.pump();
    expect(dismissed, 1);
    expect(find.byKey(const Key('health-banner')), findsNothing);
  });

  testWidgets('permission problems get the settings button but no dismiss', (tester) async {
    var opened = 0;
    await tester.pumpWidget(host(ValueNotifier(const AlarmHealth({AlarmProblem.battery, AlarmProblem.notifications})), onSettings: () => opened++));
    expect(find.text('Báo thức có thể không đáng tin'), findsOneWidget);
    expect(find.textContaining('Pin đang hạn chế'), findsOneWidget);
    expect(find.textContaining('Chưa cho phép thông báo'), findsOneWidget);
    expect(find.byKey(const Key('health-dismiss')), findsNothing);
    await tester.tap(find.byKey(const Key('health-settings')));
    expect(opened, 1);
  });

  testWidgets('follows the health as it changes', (tester) async {
    final h = ValueNotifier(AlarmHealth.ok);
    await tester.pumpWidget(host(h));
    h.value = const AlarmHealth({AlarmProblem.exactAlarm});
    await tester.pump();
    expect(find.textContaining('báo thức chính xác'), findsOneWidget);
  });
}
