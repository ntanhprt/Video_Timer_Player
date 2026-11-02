import 'package:flutter/material.dart';

import '../core/alarm.dart';
import '../core/schedule.dart';
import '../data/alarm_repository.dart';
import 'alarm_edit_page.dart';

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
  const AlarmListPage({super.key, required this.repo});

  void _open(BuildContext context, [Alarm? a]) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AlarmEditPage(repo: repo, initial: a)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Đánh thức')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(context),
        icon: const Icon(Icons.add_alarm),
        label: const Text('Thêm'),
      ),
      body: StreamBuilder<List<Alarm>>(
        stream: repo.watch(),
        builder: (context, snap) {
          final alarms = snap.data;
          if (alarms == null) return const Center(child: CircularProgressIndicator());
          if (alarms.isEmpty) return const Center(child: Text('Chưa có báo thức. Bấm "Thêm" để tạo.'));
          final now = DateTime.now();
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: alarms.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final a = alarms[i];
              final next = a.enabled ? nextFire(a.schedule, now) : null;
              return ListTile(
                title: Text(a.name),
                subtitle: Text('${a.enabled ? describeNext(next, now) : 'Đang tắt'} · ${outputLabel(a.output)}'),
                trailing: Switch(value: a.enabled, onChanged: (on) => repo.upsert(a.copyWith(enabled: on))),
                onTap: () => _open(context, a),
              );
            },
          );
        },
      ),
    );
  }
}
