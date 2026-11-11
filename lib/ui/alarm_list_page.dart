import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/alarm.dart';
import '../core/schedule.dart';
import '../alarm/alarm_scheduler.dart';
import '../data/alarm_repository.dart';
import 'about_page.dart';
import 'alarm_edit_page.dart';
import 'alarm_summary.dart';
import 'clock_header.dart';
import 'health_banner.dart';
import 'tuya_page.dart';
import '../tuya/tuya_hub.dart';
import '../alarm/ring_controller.dart';

const _short = {1: 'T2', 2: 'T3', 3: 'T4', 4: 'T5', 5: 'T6', 6: 'T7', 7: 'CN'};

String _two(int n) => n.toString().padLeft(2, '0');

String describeNext(DateTime? next, DateTime now) {
  if (next == null) return 'Không còn lần kêu nào';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(next.year, next.month, next.day);
  final diff = day.difference(today).inDays;
  final when = diff == 0 ? 'Hôm nay' : diff == 1 ? 'Ngày mai' : _short[next.weekday]!;
  return '$when ${_two(next.hour)}:${_two(next.minute)}';
}

class AlarmListPage extends StatelessWidget {
  final AlarmRepository repo;
  final AlarmScheduler scheduler;
  final RingController? ring;
  final TuyaHub? tuya;
  const AlarmListPage({super.key, required this.repo, required this.scheduler, this.ring, this.tuya});

  void _open(BuildContext context, [Alarm? a]) => Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => AlarmEditPage(repo: repo, initial: a, onTest: (alarm, log) => scheduler.testIn(alarm, const Duration(seconds: 10), log: log),
          onDownload: (urls, log) => scheduler.downloadNow(urls, log: log),
          onLibrary: scheduler.musicLibrary,
          cachedPath: scheduler.cache.cachedPath,
          titleOf: scheduler.cache.title)));

  String _music(Alarm a, Set<String> ready) {
    final urls = a.youtubeUrls.where((u) => u.trim().isNotEmpty).toList();
    final files = a.audioFiles.length;
    if (urls.isEmpty && files == 0) return 'Nhạc: dự phòng của app (chưa thêm bài nào)';
    final done = urls.where(ready.contains).length + files;
    final total = urls.length + files;
    final order = a.randomOrder ? 'ngẫu nhiên' : 'theo thứ tự';
    final state = done == 0 ? 'chưa tải xong bài nào, tạm dùng nhạc dự phòng' : '$done/$total bài sẵn sàng';
    return 'Nhạc: $total bài, phát $order • $state';
  }

  Widget _line(BuildContext context, IconData icon, String text, {Color? color}) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: color ?? Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ]),
      );

  Widget _dayChips(BuildContext context, Set<int> days, bool enabled) {
    final scheme = Theme.of(context).colorScheme;
    return Row(children: [
      for (final d in weekdayShort.entries)
        Container(
          margin: const EdgeInsets.only(right: 4),
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: days.contains(d.key) ? (enabled ? scheme.primary : scheme.outline) : Colors.transparent,
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Text(
            d.value,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: days.contains(d.key) ? scheme.onPrimary : scheme.onSurfaceVariant),
          ),
        ),
    ]);
  }

  Widget _card(BuildContext context, Alarm a, Set<String> ready, DateTime now) {
    final theme = Theme.of(context);
    final next = a.enabled ? nextFire(a.schedule, now) : null;
    final days = scheduleDays(a.schedule);
    final dim = a.enabled ? null : theme.colorScheme.onSurface.withValues(alpha: 0.5);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _open(context, a),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(scheduleHeadline(a.schedule), style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold, color: dim)),
                  Text(a.name, style: theme.textTheme.titleMedium?.copyWith(color: dim)),
                ]),
              ),
              Switch(value: a.enabled, onChanged: (on) => repo.upsert(a.copyWith(enabled: on))),
            ]),
            const SizedBox(height: 8),
            if (days != null) _dayChips(context, days, a.enabled),
            _line(context, Icons.repeat, scheduleKind(a.schedule)),
            _line(
              context,
              Icons.alarm,
              a.enabled
                  ? (next == null ? 'Không còn lần kêu nào' : 'Kêu tiếp: ${describeNext(next, now)} (${untilLabel(next, now)})')
                  : 'Đang tắt, sẽ không kêu',
              color: a.enabled ? theme.colorScheme.primary : null,
            ),
            _line(context, Icons.volume_up, volumeLabel(a.volume)),
            _line(context, Icons.timer_outlined, holdLabel(a.volume)),
            _line(context, Icons.speaker, 'Phát ra: ${outputLabel(a.output)}'),
            _line(context, Icons.music_note, _music(a, ready)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Đánh thức'), actions: [
        IconButton(
          tooltip: 'Phiên bản & có gì mới',
          icon: const Icon(Icons.info_outline),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AboutPage())),
        ),
      ]),
      bottomNavigationBar: const SafeArea(child: Padding(padding: EdgeInsets.only(right: 120), child: VersionLabel())),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(context),
        icon: const Icon(Icons.add_alarm),
        label: const Text('Thêm'),
      ),
      body: Column(children: [
        const ClockHeader(),
        HealthBanner(health: scheduler.health, onOpenSettings: openAppSettings, onDismissWiped: scheduler.dismissWiped),
        if (tuya != null) TuyaTile(hub: tuya!),
        Expanded(child: StreamBuilder<List<Alarm>>(
        stream: repo.watch(),
        builder: (context, snap) {
          final alarms = snap.data;
          if (alarms == null) return const Center(child: CircularProgressIndicator());
          if (alarms.isEmpty) return const Center(child: Text('Chưa có báo thức. Bấm "Thêm" để tạo.'));
          final now = DateTime.now();
          return ValueListenableBuilder<Set<String>>(
            valueListenable: scheduler.ready,
            builder: (context, ready, _) => ListView.separated(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: alarms.length,
            separatorBuilder: (_, _) => const SizedBox.shrink(),
            itemBuilder: (context, i) => _card(context, alarms[i], ready, now),
            ),
          );
        },
      )),
      ]),
    );
  }
}
