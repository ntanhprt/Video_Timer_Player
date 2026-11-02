import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_timer_player/core/alarm.dart';
import 'package:video_timer_player/core/schedule.dart';
import 'package:video_timer_player/core/volume_curve.dart';
import 'package:video_timer_player/data/alarm_repository.dart';
import 'package:video_timer_player/ui/alarm_edit_page.dart';

class _FakeRepo implements AlarmRepository {
  final saved = <Alarm>[];
  @override
  Future<List<Alarm>> all() async => saved;
  @override
  Future<void> upsert(Alarm a) async => saved.add(a);
  @override
  Future<void> softDelete(String id) async {}
  @override
  Stream<List<Alarm>> watch() => const Stream.empty();
}

Alarm _alarm({VolumeSpec volume = const VolumeSpec()}) => Alarm(
      id: 'a',
      name: 'Dậy',
      schedule: const Weekly(TimeOfDayMin(6, 30), {1}),
      youtubeUrl: '',
      volume: volume,
      output: OutputKind.speaker,
      enabled: true,
      rev: 1,
      updatedAt: DateTime.utc(2026),
    );

Future<_FakeRepo> _pump(WidgetTester t, Alarm initial) async {
  final repo = _FakeRepo();
  await t.pumpWidget(MaterialApp(home: AlarmEditPage(repo: repo, initial: initial)));
  return repo;
}

void main() {
  testWidgets('target below start shows the validation error and does not save', (t) async {
    final repo = await _pump(t, _alarm(volume: const VolumeSpec(start: 0.8, target: 0.3)));
    await t.tap(find.text('Lưu'));
    await t.pump();
    expect(find.text('Âm lượng đích phải lớn hơn hoặc bằng âm lượng khởi đầu.'), findsOneWidget);
    expect(repo.saved, isEmpty);
  });

  testWidgets('a valid YouTube link is saved', (t) async {
    final repo = await _pump(t, _alarm());
    await t.enterText(find.byKey(const Key('youtubeUrl')), 'https://youtu.be/dQw4w9WgXcQ');
    await t.tap(find.text('Lưu'));
    await t.pump();
    expect(repo.saved.single.youtubeUrl, 'https://youtu.be/dQw4w9WgXcQ');
  });

  testWidgets('a non-YouTube link is rejected', (t) async {
    final repo = await _pump(t, _alarm());
    await t.enterText(find.byKey(const Key('youtubeUrl')), 'https://example.com/x');
    await t.tap(find.text('Lưu'));
    await t.pump();
    expect(find.textContaining('địa chỉ YouTube'), findsOneWidget);
    expect(repo.saved, isEmpty);
  });
}
