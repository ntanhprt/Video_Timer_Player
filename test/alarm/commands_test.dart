import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_timer_player/alarm/commands/builtin.dart';
import 'package:video_timer_player/alarm/commands/custom.dart';
import 'package:video_timer_player/alarm/commands/intent.dart';
import 'package:video_timer_player/alarm/commands/registry.dart';
import 'package:video_timer_player/alarm/voice_command.dart';

CommandRegistry registry() => CommandRegistry()..registerAll(builtinIntents());

IntentMatch? match(CommandRegistry r, String s) => r.match(tokenizeVietnamese(s));

class Recorder {
  final calls = <String>[];
  final said = <String>[];
  late final ctx = CommandContext(
    stop: () async => calls.add('stop'),
    snooze: (d) async => calls.add('snooze ${d.inMinutes}'),
    say: said.add,
    now: () => DateTime(2026, 11, 3, 6, 5),
    describeCommands: () => ['a', 'b'],
  );
}

void main() {
  group('matching', () {
    final r = registry();

    test('built-in commands are found by id', () {
      expect(match(r, 'tắt chuông đi')!.intent.id, 'stop');
      expect(match(r, 'dậy rồi')!.intent.id, 'stop');
      expect(match(r, 'mấy giờ rồi')!.intent.id, 'time');
      expect(match(r, 'các lệnh')!.intent.id, 'help');
    });

    test('snooze reads the time; "10 phút nữa" alone also snoozes', () {
      expect(match(r, 'mười phút nữa báo lại')!.args['delay'], const Duration(minutes: 10));
      expect(match(r, 'báo lại')!.args['delay'], defaultVoiceSnooze);
      final m = match(r, 'hai mươi phút nữa')!;
      expect(m.intent.id, 'snooze');
      expect(m.args['delay'], const Duration(minutes: 20));
    });

    test('snooze beats stop in one sentence', () {
      expect(match(r, 'tắt đi mười phút nữa báo lại')!.intent.id, 'snooze');
    });

    test('a one-letter slip in a longer word is forgiven; nonsense is not', () {
      expect(match(r, 'tắt chuôn đi')!.intent.id, 'stop');
      expect(match(r, 'bật đèn lên'), isNull);
      expect(match(r, 'xin chào các bạn'), isNull);
      expect(match(r, ''), isNull);
    });

    test('forgiving one slip lowers the score below an exact match', () {
      expect(match(r, 'tắt chuông')!.score, 1.0);
      expect(match(r, 'tắt chuôn')!.score, lessThan(1.0));
    });
  });

  group('registry', () {
    test('a new command can be added without touching the others', () {
      final r = registry();
      final rec = Recorder();
      r.register(VoiceIntent(
        id: 'light',
        title: 'Bật đèn',
        examples: ['bật đèn lên'],
        patterns: ['bật đèn'],
        run: (ctx, args) async {
          ctx.say('đã bật đèn');
          return 'ok';
        },
      ));
      final m = match(r, 'bật đèn lên đi')!;
      expect(m.intent.id, 'light');
      m.intent.run(rec.ctx, m.args);
      expect(rec.said, ['đã bật đèn']);
      expect(match(r, 'tắt chuông đi')!.intent.id, 'stop');
      r.unregister('light');
      expect(match(r, 'bật đèn lên'), isNull);
    });

    test('built-in commands run through the context', () async {
      final r = registry();
      final rec = Recorder();
      var m = match(r, 'mười lăm phút nữa báo lại')!;
      expect(await m.intent.run(rec.ctx, m.args), 'Báo lại sau 15 phút');
      m = match(r, 'tắt chuông đi')!;
      await m.intent.run(rec.ctx, m.args);
      m = match(r, 'mấy giờ rồi')!;
      expect(await m.intent.run(rec.ctx, m.args), 'Bây giờ là 06:05');
      expect(rec.calls, ['snooze 15', 'stop']);
    });

    test('describe lists commands with an example', () {
      expect(registry().describe(), contains(startsWith('Tắt chuông — nói: "tắt chuông đi"')));
    });
  });

  group('custom commands', () {
    test('a taught phrase maps to its action and outranks built-ins', () async {
      final r = registry();
      r.register(customIntent(0, const CustomCommand(phrase: 'cho tôi ngủ nốt', action: 'snooze', minutes: 20)));
      final m = match(r, 'cho tôi ngủ nốt đi')!;
      expect(m.intent.id, '${customPrefix}0');
      final rec = Recorder();
      await m.intent.run(rec.ctx, m.args);
      expect(rec.calls, ['snooze 20']);
    });

    test('a taught phrase tolerates a slip and rejects unrelated speech', () {
      final r = registry();
      r.register(customIntent(0, const CustomCommand(phrase: 'ngừng kêu', action: 'stop')));
      expect(match(r, 'ngừng kêu')!.intent.id, '${customPrefix}0');
      expect(match(r, 'ngưng kêu đi')!.intent.id, '${customPrefix}0');
      expect(match(r, 'hôm nay trời đẹp'), isNull);
    });

    test('the store round-trips and survives a missing or broken file', () async {
      final dir = await Directory.systemTemp.createTemp('cmds');
      final file = File('${dir.path}/c.json');
      final store = CustomCommandStore(file);
      expect(await store.load(), isEmpty);
      const list = [CustomCommand(phrase: 'a b', action: 'stop'), CustomCommand(phrase: 'c d', action: 'snooze', minutes: 7)];
      await store.save(list);
      expect(await store.load(), list);
      await file.writeAsString('not json');
      expect(await store.load(), isEmpty);
      await dir.delete(recursive: true);
    });
  });
}
