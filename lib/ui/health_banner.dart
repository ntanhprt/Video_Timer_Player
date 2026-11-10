import 'package:flutter/material.dart';

import '../alarm/alarm_health.dart';

String problemText(AlarmProblem p) => switch (p) {
      AlarmProblem.wiped =>
        'Hệ thống đã xóa báo thức của app (app từng bị dừng hẳn, thường do dọn dẹp bộ nhớ của MIUI hoặc vuốt tắt app). '
            'Báo thức trong khoảng đó có thể đã không kêu. App vừa đăng ký lại, nhưng nếu app lại bị dừng thì báo thức sẽ mất tiếp.',
      AlarmProblem.notifications => 'Chưa cho phép thông báo: chuông có thể không hiện lên màn hình.',
      AlarmProblem.exactAlarm => 'Chưa cho phép báo thức chính xác: chuông có thể kêu trễ.',
      AlarmProblem.battery => 'Pin đang hạn chế app: bật "Không hạn chế" để app không bị hệ thống dừng.',
    };

/// Tells the user what makes the alarm unreliable, with the one thing to do about it.
class HealthBanner extends StatelessWidget {
  final ValueListenable<AlarmHealth> health;
  final VoidCallback onOpenSettings;
  final VoidCallback onDismissWiped;
  const HealthBanner({super.key, required this.health, required this.onOpenSettings, required this.onDismissWiped});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AlarmHealth>(
      valueListenable: health,
      builder: (context, h, _) {
        if (h.isOk) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        final urgent = h.wiped;
        final bg = urgent ? scheme.errorContainer : scheme.tertiaryContainer;
        final fg = urgent ? scheme.onErrorContainer : scheme.onTertiaryContainer;
        // The wipe first, then the rest in a stable order.
        final ordered = [for (final p in AlarmProblem.values) if (h.problems.contains(p)) p];
        return Container(
          key: const Key('health-banner'),
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(urgent ? Icons.warning_amber_rounded : Icons.info_outline, color: fg),
              const SizedBox(width: 8),
              Text(urgent ? 'Báo thức có thể đã bị lỡ' : 'Báo thức có thể không đáng tin',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(color: fg, fontWeight: FontWeight.bold)),
            ]),
            for (final p in ordered)
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 4),
                child: Text(problemText(p), style: TextStyle(color: fg)),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(children: [
                if (h.wiped) TextButton(key: const Key('health-dismiss'), onPressed: onDismissWiped, child: const Text('Đã hiểu')),
                TextButton(key: const Key('health-settings'), onPressed: onOpenSettings, child: const Text('Mở cài đặt app')),
              ]),
            ),
          ]),
        );
      },
    );
  }
}
