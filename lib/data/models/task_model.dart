import 'package:isar/isar.dart';
import 'device_model.dart';

part 'task_model.g.dart';

@collection
class TaskModel {
  Id id = Isar.autoIncrement;

  late String name;
  late int intervalDays;
  DateTime? lastCompletedAt;

  final device = IsarLink<DeviceModel>();

  // Helper method to get the next due date
  @ignore
  DateTime get nextDueDate {
    if (lastCompletedAt == null) {
      return DateTime.now(); // Due immediately if never completed
    }
    return lastCompletedAt!.add(Duration(days: intervalDays));
  }

  // Calculate days remaining (negative means overdue)
  @ignore
  int get daysRemaining {
    final now = DateTime.now();
    final due = nextDueDate;
    // Difference in days considering just dates could be better, but simple difference is fine for now
    final dateNow = DateTime(now.year, now.month, now.day);
    final dateDue = DateTime(due.year, due.month, due.day);
    return dateDue.difference(dateNow).inDays;
  }
}
