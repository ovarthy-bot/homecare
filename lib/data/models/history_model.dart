import 'package:isar/isar.dart';

part 'history_model.g.dart';

@collection
class HistoryModel {
  Id id = Isar.autoIncrement;

  late String deviceName;
  late String taskName;
  late DateTime completedAt;
  
  int? deviceId;

  static const sourceWeb = 'web';

  /// Kaydın nereden geldiği: `null` uygulama, [sourceWeb] uygulaması olmayan telefondan.
  String? source;

  /// Ara depodaki kayıt numarası; aynı kaydın iki kez içe aktarılmasını önler.
  String? externalId;
}
