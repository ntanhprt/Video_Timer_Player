import 'package:flutter_test/flutter_test.dart';
import 'package:video_timer_player/alarm/voice_command.dart';

SnoozeCommand snooze(int minutes) => SnoozeCommand(Duration(minutes: minutes));

void main() {
  grammarTests();
  test('stop phrases', () {
    for (final s in ['tắt chuông đi', 'Tắt báo thức', 'tắt nhạc đi', 'dừng lại', 'im đi', 'thôi đi', 'tat chuong di']) {
      expect(parseVoiceCommand(s), const StopCommand(), reason: s);
    }
  });

  test('snooze with Vietnamese number words', () {
    expect(parseVoiceCommand('mười phút nữa báo lại'), snooze(10));
    expect(parseVoiceCommand('năm phút nữa báo lại'), snooze(5));
    expect(parseVoiceCommand('mười lăm phút nữa báo lại'), snooze(15));
    expect(parseVoiceCommand('hai mươi phút nữa báo lại'), snooze(20));
    expect(parseVoiceCommand('ba mươi phút nữa báo lại'), snooze(30));
    expect(parseVoiceCommand('hai mươi lăm phút nữa báo lại'), snooze(25));
    expect(parseVoiceCommand('bốn mươi lăm phút nữa báo lại'), snooze(45));
    expect(parseVoiceCommand('sáu phút nữa báo lại'), snooze(6));
  });

  test('snooze with digits and hours', () {
    expect(parseVoiceCommand('10 phút nữa báo lại'), snooze(10));
    expect(parseVoiceCommand('báo lại sau 15 phút'), snooze(15));
    expect(parseVoiceCommand('một tiếng nữa báo lại'), snooze(60));
    expect(parseVoiceCommand('1 giờ nữa báo lại'), snooze(60));
    expect(parseVoiceCommand('một tiếng rưỡi nữa báo lại'), snooze(90));
    expect(parseVoiceCommand('nửa tiếng nữa báo lại'), snooze(30));
  });

  test('"sau" before a number is the word "after", not six', () {
    expect(parseVoiceCommand('sau mười phút báo lại'), snooze(10));
  });

  test('snooze without a time uses the default; huge times are capped', () {
    expect(parseVoiceCommand('báo lại'), const SnoozeCommand(defaultVoiceSnooze));
    expect(parseVoiceCommand('một trăm giờ nữa báo lại'), isA<SnoozeCommand>());
    expect(parseVoiceCommand('99 giờ nữa báo lại'), const SnoozeCommand(maxVoiceSnooze));
  });

  test('snoozing wins over stopping in one sentence', () {
    expect(parseVoiceCommand('tắt đi, mười phút nữa báo lại'), snooze(10));
  });

  test('other speech is ignored', () {
    for (final s in ['', 'xin chào', 'hôm nay trời đẹp', 'tắt', 'bật đèn lên']) {
      expect(parseVoiceCommand(s), isNull, reason: s);
    }
  });
}

void grammarTests() {
  group('voice grammar', () {
    test('viNumber speaks Vietnamese numbers', () {
      expect(viNumber(5), 'năm');
      expect(viNumber(10), 'mười');
      expect(viNumber(15), 'mười lăm');
      expect(viNumber(21), 'hai mươi mốt');
      expect(viNumber(25), 'hai mươi lăm');
      expect(viNumber(45), 'bốn mươi lăm');
    });

    test('every spoken snooze phrase parses back to the same minutes', () {
      for (final m in voiceSnoozeMinutes) {
        expect(parseVoiceCommand('${viNumber(m)} phút nữa báo lại'), snooze(m), reason: '$m');
        expect(parseVoiceCommand('báo lại sau ${viNumber(m)} phút'), snooze(m), reason: '$m');
      }
    });

    test('every phrase in the grammar is understood', () {
      for (final p in voicePhrases()) {
        expect(parseVoiceCommand(p), isNotNull, reason: p);
      }
    });
  });
}
