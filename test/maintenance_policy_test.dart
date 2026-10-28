import 'package:flutter_test/flutter_test.dart';
import 'package:homecare/data/models/task_model.dart';
import 'package:homecare/features/maintenance/maintenance_policy.dart';

TaskModel task(String name, {required int intervalDays, required int completedDaysAgo}) {
  return TaskModel()
    ..name = name
    ..intervalDays = intervalDays
    ..lastCompletedAt = DateTime.now().subtract(Duration(days: completedDaysAgo));
}

List<String> names(List<TaskModel> tasks) => tasks.map((t) => t.name).toList();

void main() {
  group('MaintenancePolicy.tasksToRecord', () {
    test('görevi olmayan cihaz için boş liste döner', () {
      expect(MaintenancePolicy.tasksToRecord(const []), isEmpty);
    });

    test('zamanı gelmiş ve geçmiş tüm görevleri seçer, gelmemiş olanı seçmez', () {
      final selected = MaintenancePolicy.tasksToRecord([
        task('Çöp haznesi', intervalDays: 7, completedDaysAgo: 10), // 3 gün gecikmiş
        task('Demlik', intervalDays: 7, completedDaysAgo: 7), // bugün
        task('Kireç çözme', intervalDays: 60, completedDaysAgo: 5), // 55 gün var
      ]);

      expect(names(selected), ['Çöp haznesi', 'Demlik']);
    });

    test('hiç tamamlanmamış görev bugün zamanı gelmiş sayılır', () {
      final never = TaskModel()
        ..name = 'Yeni görev'
        ..intervalDays = 30;

      expect(names(MaintenancePolicy.tasksToRecord([never])), ['Yeni görev']);
    });

    test('hiçbirinin zamanı gelmediyse en yakın tarihli tek görevi seçer', () {
      final selected = MaintenancePolicy.tasksToRecord([
        task('Kireç çözme', intervalDays: 60, completedDaysAgo: 5), // 55 gün
        task('Filtre', intervalDays: 30, completedDaysAgo: 10), // 20 gün
        task('Fırça', intervalDays: 90, completedDaysAgo: 1), // 89 gün
      ]);

      expect(names(selected), ['Filtre']);
    });

    test('eşit uzaklıktaki görevlerde listedeki ilkini seçer', () {
      final selected = MaintenancePolicy.tasksToRecord([
        task('Birinci', intervalDays: 30, completedDaysAgo: 10),
        task('İkinci', intervalDays: 30, completedDaysAgo: 10),
      ]);

      expect(names(selected), ['Birinci']);
    });
  });
}
