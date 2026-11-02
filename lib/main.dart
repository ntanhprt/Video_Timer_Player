import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'data/alarm_repository.dart';
import 'ui/alarm_list_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repo = await SqliteAlarmRepository.open(p.join(await getDatabasesPath(), 'alarms.db'));
  runApp(App(repo: repo));
}

class App extends StatelessWidget {
  final AlarmRepository repo;
  const App({super.key, required this.repo});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Đánh thức',
      theme: ThemeData(colorSchemeSeed: Colors.deepOrange, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: Colors.deepOrange, useMaterial3: true, brightness: Brightness.dark),
      home: AlarmListPage(repo: repo),
    );
  }
}
