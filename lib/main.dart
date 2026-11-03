import 'dart:io';

import 'package:alarm/alarm.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite/sqflite.dart';

import 'alarm/alarm_scheduler.dart';
import 'alarm/commands/custom.dart';
import 'alarm/ring_controller.dart';
import 'alarm/youtube_cache.dart';
import 'data/alarm_repository.dart';
import 'ui/alarm_list_page.dart';
import 'ui/ringing_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Alarm.init();
  final repo = await SqliteAlarmRepository.open(p.join(await getDatabasesPath(), 'alarms.db'));
  final scheduler = AlarmScheduler(repo, YoutubeCache());
  // Every edit re-registers the native alarms; so does coming back to the app.
  repo.watch().listen((_) => scheduler.sync());
  WidgetsBinding.instance.addObserver(_OnResume(scheduler.sync));
  final support = await getApplicationSupportDirectory();
  final ring = RingController(onSnooze: snooze, store: CustomCommandStore(File(p.join(support.path, 'voice_commands.json'))))..start();
  runApp(App(repo: repo, scheduler: scheduler, voiceStatus: ring.voiceStatus, voiceLevel: ring.voiceLevel, ring: ring));
  _askPermissions();
}

/// The alarm cannot ring reliably without these; asked once the first screen is up.
Future<void> _askPermissions() async {
  await Permission.notification.request();
  await Permission.scheduleExactAlarm.request();
  await Permission.ignoreBatteryOptimizations.request();
  // For "tắt chuông đi" / "mười phút nữa báo lại" while an alarm rings.
  await Permission.microphone.request();
}

class _OnResume with WidgetsBindingObserver {
  final Future<void> Function() onResume;
  _OnResume(this.onResume);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}

class App extends StatelessWidget {
  final AlarmRepository repo;
  final AlarmScheduler scheduler;
  final ValueListenable<String>? voiceStatus;
  final ValueListenable<double>? voiceLevel;
  final RingController? ring;
  const App({super.key, required this.repo, required this.scheduler, this.voiceStatus, this.voiceLevel, this.ring});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Đánh thức',
      theme: ThemeData(colorSchemeSeed: Colors.deepOrange, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: Colors.deepOrange, useMaterial3: true, brightness: Brightness.dark),
      builder: (context, child) => RingingOverlay(voiceStatus: voiceStatus, voiceLevel: voiceLevel, child: child!),
      home: AlarmListPage(repo: repo, scheduler: scheduler, ring: ring),
    );
  }
}
