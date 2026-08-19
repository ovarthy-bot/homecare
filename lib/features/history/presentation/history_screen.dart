import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../data/models/history_model.dart';
import '../../dashboard/presentation/providers/dashboard_providers.dart';

final historyProvider = StreamProvider<List<HistoryModel>>((ref) {
  final isarService = ref.watch(isarServiceProvider);
  return isarService.listenToHistory();
});

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsyncValue = ref.watch(historyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Geçmiş İşlemler')),
      body: historyAsyncValue.when(
        data: (historyLogs) {
          if (historyLogs.isEmpty) {
            return const Center(child: Text('Henüz tamamlanmış bir görev yok.'));
          }
          return ListView.builder(
            itemCount: historyLogs.length,
            itemBuilder: (context, index) {
              final log = historyLogs[index];
              return ListTile(
                leading: const Icon(Icons.check_circle, color: Colors.green),
                title: Text(log.taskName),
                subtitle: Text(log.deviceName),
                trailing: Text(DateFormat('dd.MM.yyyy HH:mm').format(log.completedAt)),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Hata: $e')),
      ),
    );
  }
}
