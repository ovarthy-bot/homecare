import 'package:isar/isar.dart';
import 'task_model.dart';

part 'device_model.g.dart';

@collection
class DeviceModel {
  Id id = Isar.autoIncrement;

  late String name;
  late String room;
  String? category;

  /// Marka/model bilgisi (ör. "Epson EcoTank L3250").
  String? modelInfo;
  double? price;

  String? notes;
  String? serviceInfo;
  DateTime? purchaseDate;
  String? imagePath;
  int warrantyMonths = 24;
  
  @Backlink(to: 'device')
  final tasks = IsarLinks<TaskModel>();

  /// Garantinin bittiği gün; satın alma tarihi yoksa `null`. Ay sonlarında taşmaz
  /// (31 Ocak + 1 ay = 28/29 Şubat).
  @ignore
  DateTime? get warrantyEndDate {
    final purchase = purchaseDate;
    if (purchase == null) return null;
    final months = purchase.month - 1 + warrantyMonths;
    final year = purchase.year + months ~/ 12;
    final month = months % 12 + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, purchase.day < lastDay ? purchase.day : lastDay);
  }
}
