import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/device_model.dart';
import '../../../data/models/history_model.dart';
import '../../../data/models/task_model.dart';
import '../../dashboard/presentation/providers/dashboard_providers.dart';
import '../timeline.dart';

final historyProvider = StreamProvider<List<HistoryModel>>((ref) {
  final isarService = ref.watch(isarServiceProvider);
  return isarService.listenToHistory();
});

class _UpcomingTask {
  final DeviceModel device;
  final TaskModel task;

  const _UpcomingTask(this.device, this.task);
}

class HistoryScreen extends ConsumerWidget {
  /// Dashboard'daki "yaklaşan bakım" eşiğiyle aynı.
  static const _upcomingWithinDays = 14;
  static const _upcomingLimit = 5;

  const HistoryScreen({super.key});

  List<_UpcomingTask> _upcomingTasks(List<DeviceModel> devices) {
    final tasks = [
      for (final device in devices)
        for (final task in device.tasks)
          if (task.daysRemaining <= _upcomingWithinDays) _UpcomingTask(device, task),
    ]..sort((a, b) => a.task.daysRemaining.compareTo(b.task.daysRemaining));
    return tasks.take(_upcomingLimit).toList();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsyncValue = ref.watch(historyProvider);
    final upcoming = _upcomingTasks(ref.watch(devicesProvider).value ?? const []);

    return Scaffold(
      appBar: AppBar(title: const Text('Geçmiş İşlemler')),
      body: historyAsyncValue.when(
        data: (historyLogs) {
          final now = DateTime.now();
          final days = groupHistoryByDay(historyLogs);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (upcoming.isNotEmpty) ...[
                _SectionTitle('Yaklaşan Bakımlar'),
                for (final item in upcoming) _UpcomingRow(item: item),
                const SizedBox(height: 24),
              ],
              _SectionTitle('Zaman Çizelgesi'),
              if (days.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('Henüz tamamlanmış bir görev yok.')),
                ),
              for (final day in days) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 4),
                  child: Text(
                    timelineDayLabel(day.day, now),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppTheme.textSecondary),
                  ),
                ),
                for (final log in day.entries) _TimelineEntry(log: log),
              ],
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Hata: $e')),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}

class _UpcomingRow extends StatelessWidget {
  final _UpcomingTask item;

  const _UpcomingRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final days = item.task.daysRemaining;
    final overdue = days < 0;
    final color = overdue ? AppTheme.statusOverdue : AppTheme.statusUpcoming;
    final status = overdue
        ? '${-days} gün gecikti'
        : days == 0
            ? 'Bugün'
            : '$days gün sonra';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(overdue ? Icons.warning_amber_rounded : Icons.schedule, color: color),
        title: Text(item.task.name),
        subtitle: Text(item.device.name),
        trailing: Text(status, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color)),
        onTap: () => context.push('/device/${item.device.id}'),
      ),
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  final HistoryModel log;

  const _TimelineEntry({required this.log});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                Positioned.fill(
                  child: Center(child: Container(width: 2, color: AppTheme.surfaceVariant)),
                ),
                Container(
                  margin: const EdgeInsets.only(top: 18),
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(color: AppTheme.statusNormal, shape: BoxShape.circle),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${log.taskName} yapıldı', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 2),
                          Text(log.deviceName, style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                    Text(
                      DateFormat('HH:mm').format(log.completedAt),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
