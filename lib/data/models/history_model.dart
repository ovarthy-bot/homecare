import 'package:isar/isar.dart';

part 'history_model.g.dart';

@collection
class HistoryModel {
  Id id = Isar.autoIncrement;

  late String deviceName;
  late String taskName;
  late DateTime completedAt;
  
  int? deviceId;
}
