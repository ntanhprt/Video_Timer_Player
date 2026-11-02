import 'dart:async';
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/alarm.dart';

abstract class AlarmRepository {
  /// Alarms that have not been deleted.
  Future<List<Alarm>> all();

  /// Saves [a], bumping its `rev` and stamping `updatedAt`.
  Future<void> upsert(Alarm a);

  /// Marks the alarm deleted; the row is kept so sync can tell other devices.
  Future<void> softDelete(String id);

  /// Emits the current list, then again after every change.
  Stream<List<Alarm>> watch();
}

class SqliteAlarmRepository implements AlarmRepository {
  final Database _db;
  final DateTime Function() _now;
  final _changes = StreamController<void>.broadcast();

  SqliteAlarmRepository._(this._db, this._now);

  static Future<SqliteAlarmRepository> open(String path, {DateTime Function()? clock}) async {
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, _) => db.execute(
        'CREATE TABLE alarms (id TEXT PRIMARY KEY, rev INTEGER NOT NULL, deleted INTEGER NOT NULL, json TEXT NOT NULL)',
      ),
    );
    return SqliteAlarmRepository._(db, clock ?? DateTime.now);
  }

  /// Every row including deleted ones, for sync.
  Future<List<Alarm>> allIncludingDeleted() async => _read(await _db.query('alarms', orderBy: 'id'));

  @override
  Future<List<Alarm>> all() async => _read(await _db.query('alarms', where: 'deleted = 0', orderBy: 'id'));

  List<Alarm> _read(List<Map<String, Object?>> rows) =>
      [for (final r in rows) Alarm.fromJson(jsonDecode(r['json'] as String) as Map<String, dynamic>)];

  @override
  Future<void> upsert(Alarm a) async {
    final prev = await _db.query('alarms', columns: ['rev'], where: 'id = ?', whereArgs: [a.id]);
    final rev = prev.isEmpty ? 1 : (prev.first['rev'] as int) + 1;
    await _write(a.copyWith(rev: rev, updatedAt: _now()));
  }

  @override
  Future<void> softDelete(String id) async {
    final rows = await _db.query('alarms', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return;
    final a = Alarm.fromJson(jsonDecode(rows.first['json'] as String) as Map<String, dynamic>);
    await _write(a.copyWith(rev: a.rev + 1, updatedAt: _now(), deleted: true));
  }

  Future<void> _write(Alarm a) async {
    await _db.insert(
      'alarms',
      {'id': a.id, 'rev': a.rev, 'deleted': a.deleted ? 1 : 0, 'json': jsonEncode(a.toJson())},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _changes.add(null);
  }

  @override
  Stream<List<Alarm>> watch() async* {
    yield await all();
    yield* _changes.stream.asyncMap((_) => all());
  }
}
