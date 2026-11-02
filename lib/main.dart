import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite/sqflite.dart';

import 'alarm/alarm_scheduler.dart';
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
  runApp(App(repo: repo, scheduler: scheduler));
  _askPermissions();
}

/// The alarm cannot ring reliably without these; asked once the first screen is up.
Future<void> _askPermissions() async {
  await Permission.notification.request();
  await Permission.scheduleExactAlarm.request();
  await Permission.ignoreBatteryOptimizations.request();
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
  const App({super.key, required this.repo, required this.scheduler});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Đánh thức',
      theme: ThemeData(colorSchemeSeed: Colors.deepOrange, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: Colors.deepOrange, useMaterial3: true, brightness: Brightness.dark),
      builder: (context, child) => RingingOverlay(child: child!),
      home: AlarmListPage(repo: repo, scheduler: scheduler),
    );
  }
}
