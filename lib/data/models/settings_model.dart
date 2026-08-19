import 'package:isar/isar.dart';

part 'settings_model.g.dart';

@collection
class SettingsModel {
  Id id = Isar.autoIncrement;

  bool notificationsEnabled = true;
  int defaultReminderDays = 3;
}
