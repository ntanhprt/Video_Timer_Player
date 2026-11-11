import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_timer_player/alarm/music_library.dart';
import 'package:video_timer_player/ui/library_sheet.dart';

LibraryTrack _t(String name, {String? url, bool youtube = true}) =>
    (path: '/m/$name.m4a', name: name, url: url, bytes: 3 * 1048576, modified: DateTime(2026), youtube: youtube);

void main() {
  Future<void> open(WidgetTester t, List<LibraryTrack> tracks, {bool Function(LibraryTrack)? alreadyIn}) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showModalBottomSheet<List<LibraryTrack>>(context: context, builder: (_) => LibrarySheet(tracks: tracks, alreadyIn: alreadyIn ?? (_) => false)),
            child: const Text('mở'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('mở'));
    await t.pumpAndSettle();
  }

  testWidgets('says so when there is nothing on the phone', (t) async {
    await open(t, const []);
    expect(find.textContaining('Chưa có bài nào trong máy'), findsOneWidget);
  });

  testWidgets('ticked tracks come back, in list order', (t) async {
    final a = _t('Một', url: 'https://youtu.be/1');
    final b = _t('Hai', youtube: false);
    final c = _t('Ba', url: 'https://youtu.be/3');
    List<LibraryTrack>? got;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => got = await showModalBottomSheet<List<LibraryTrack>>(context: context, builder: (_) => LibrarySheet(tracks: [a, b, c], alreadyIn: (_) => false)),
            child: const Text('mở'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('mở'));
    await t.pumpAndSettle();
    expect(find.text('Chọn bài để thêm'), findsOneWidget);
    await t.tap(find.byKey(Key('lib-${c.path}')));
    await t.tap(find.byKey(Key('lib-${a.path}')));
    await t.pump();
    expect(find.text('Thêm 2 bài'), findsOneWidget);
    await t.tap(find.byKey(const Key('library-add')));
    await t.pumpAndSettle();
    expect(got, [a, c]);
  });

  testWidgets('a track already in the alarm is ticked and cannot be added twice', (t) async {
    final a = _t('Một');
    await open(t, [a], alreadyIn: (x) => x.path == a.path);
    expect(find.textContaining('đã có trong danh sách'), findsOneWidget);
    expect(tester(t, a).value, isTrue);
    await t.tap(find.byKey(Key('lib-${a.path}')));
    await t.pump();
    expect(find.text('Chọn bài để thêm'), findsOneWidget);
  });
}

CheckboxListTile tester(WidgetTester t, LibraryTrack a) => t.widget<CheckboxListTile>(find.byKey(Key('lib-${a.path}')));
