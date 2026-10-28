import '../../data/models/task_model.dart';

class MaintenancePolicy {
  /// Karekod okutulduğunda hangi görevlerin "yapıldı" sayılacağını seçer.
  ///
  /// Zamanı gelmiş veya geçmiş tüm görevler kaydedilir. Hiçbiri zamanı gelmemişse
  /// kullanıcı bakımı erken yapmıştır; en yakın tarihli tek görev kaydedilir.
  static List<TaskModel> tasksToRecord(Iterable<TaskModel> tasks) {
    final all = tasks.toList();
    if (all.isEmpty) return const [];

    final due = all.where((t) => t.daysRemaining <= 0).toList();
    if (due.isNotEmpty) return due;

    // Eşitlikte listedeki ilk görev kalır.
    return [all.reduce((a, b) => b.daysRemaining < a.daysRemaining ? b : a)];
  }
}
