import 'package:isar/isar.dart';
import 'task_model.dart';

part 'device_model.g.dart';

@collection
class DeviceModel {
  Id id = Isar.autoIncrement;

  late String name;
  late String room;
  String? category;

  String? notes;
  String? serviceInfo;
  DateTime? purchaseDate;
  String? imagePath;
  int warrantyMonths = 24;
  
  @Backlink(to: 'device')
  final tasks = IsarLinks<TaskModel>();
}
