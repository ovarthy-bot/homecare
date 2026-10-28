import 'package:isar/isar.dart';

part 'settings_model.g.dart';

@collection
class SettingsModel {
  Id id = Isar.autoIncrement;

  bool notificationsEnabled = true;
  int defaultReminderDays = 3;
  String? githubToken;

  /// Google Apps Script web uygulaması adresi (ara depo); boşsa web'den kayıt kapalıdır.
  String? backendUrl;

  /// Ara depodaki SECRET ile aynı gizli anahtar. Karekod anahtarları buradan türetilir.
  String? syncKey;
}
