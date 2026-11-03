import '../voice_command.dart';
import 'intent.dart';

String _two(int n) => n.toString().padLeft(2, '0');

/// The commands that come with the app.
List<VoiceIntent> builtinIntents() => [
      VoiceIntent(
        id: 'snooze',
        title: 'Báo lại sau một lúc',
        examples: ['mười phút nữa báo lại', 'báo lại sau một tiếng', 'nửa tiếng nữa báo lại'],
        patterns: ['báo lại', 'nhắc lại', 'ngủ thêm', 'hoãn lại', 'báo thức lại', 'kêu lại'],
        // "mười phút nữa" on its own also means snooze.
        when: (t) => t.contains('nua') && readTimeAmount(t) != null,
        slots: (t) => {'delay': clampSnooze(readTimeAmount(t))},
        priority: 5,
        endsRing: true,
        run: (ctx, args) async {
          final d = args['delay'] as Duration;
          await ctx.snooze(d);
          return 'Báo lại sau ${d.inMinutes} phút';
        },
      ),
      VoiceIntent(
        id: 'stop',
        title: 'Tắt chuông',
        examples: ['tắt chuông đi', 'dậy rồi', 'dừng lại'],
        patterns: [
          'tắt chuông', 'tắt báo thức', 'tắt nhạc', 'tắt đi', 'tắt hết', 'tắt máy', 'tắt loa', 'tắt đồng hồ',
          'dừng lại', 'dừng chuông', 'dừng nhạc', 'im đi', 'im lặng', 'thôi đi', 'hết chuông',
          'dậy rồi', 'tỉnh rồi', 'đã dậy',
        ],
        priority: 1,
        endsRing: true,
        run: (ctx, args) async {
          await ctx.stop();
          return 'Đã tắt chuông';
        },
      ),
      VoiceIntent(
        id: 'time',
        title: 'Hỏi giờ',
        examples: ['mấy giờ rồi'],
        patterns: ['mấy giờ', 'bây giờ là mấy giờ', 'giờ mấy'],
        run: (ctx, args) async {
          final n = ctx.now();
          return 'Bây giờ là ${_two(n.hour)}:${_two(n.minute)}';
        },
      ),
      VoiceIntent(
        id: 'help',
        title: 'Xem các lệnh',
        examples: ['các lệnh'],
        patterns: ['các lệnh', 'lệnh gì', 'hướng dẫn', 'giúp tôi'],
        run: (ctx, args) async => ctx.describeCommands().join('\n'),
      ),
    ];
