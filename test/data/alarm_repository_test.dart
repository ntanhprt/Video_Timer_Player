import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:video_timer_player/core/alarm.dart';
import 'package:video_timer_player/core/schedule.dart';
import 'package:video_timer_player/core/volume_curve.dart';
import 'package:video_timer_player/data/alarm_repository.dart';

Alarm _alarm(String id) => Alarm(
      id: id,
      name: 'Dậy',
      schedule: const Weekly(TimeOfDayMin(6, 30), {1, 2, 3}),
      youtubeUrl: '',
      volume: const VolumeSpec(),
      output: OutputKind.speaker,
      enabled: true,
      rev: 0,
      updatedAt: DateTime.utc(2026),
    );

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late SqliteAlarmRepository repo;
  final stamp = DateTime.utc(2026, 11, 2, 7);

  setUp(() async {
    repo = await SqliteAlarmRepository.open(inMemoryDatabasePath, clock: () => stamp);
  });

  test('upsert then all returns the alarm, stamped with updatedAt', () async {
    await repo.upsert(_alarm('a'));
    final list = await repo.all();
    expect(list, hasLength(1));
    expect(list.single.name, 'Dậy');
    expect(list.single.updatedAt, stamp);
  });

  test('upserting twice raises rev from 1 to 2', () async {
    await repo.upsert(_alarm('a'));
    expect((await repo.all()).single.rev, 1);
    await repo.upsert(_alarm('a').copyWith(name: 'Dậy sớm'));
    final a = (await repo.all()).single;
    expect(a.rev, 2);
    expect(a.name, 'Dậy sớm');
  });

  test('softDelete hides the alarm from all() but keeps the row', () async {
    await repo.upsert(_alarm('a'));
    await repo.softDelete('a');
    expect(await repo.all(), isEmpty);
    final raw = await repo.allIncludingDeleted();
    expect(raw.single.deleted, isTrue);
    expect(raw.single.rev, 2);
  });

  test('softDelete of an unknown id does nothing', () async {
    await repo.softDelete('nope');
    expect(await repo.allIncludingDeleted(), isEmpty);
  });

  test('watch emits the current list then each change', () async {
    final seen = <int>[];
    final sub = repo.watch().listen((l) => seen.add(l.length));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await repo.upsert(_alarm('a'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await repo.softDelete('a');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();
    expect(seen, [0, 1, 0]);
  });
}
