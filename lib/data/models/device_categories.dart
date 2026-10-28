import 'package:flutter/material.dart';

class DeviceCategory {
  final String label;
  final IconData icon;

  const DeviceCategory(this.label, this.icon);
}

/// Cihazlar etiket (label) olarak kaydedilir; liste sonradan genişletilebilir.
class DeviceCategories {
  static const kitchen = DeviceCategory('Mutfak Aletleri', Icons.coffee_maker_outlined);
  static const climate = DeviceCategory('Isıtma & Soğutma', Icons.thermostat);
  static const filters = DeviceCategory('Filtre & Arıtma', Icons.water_drop_outlined);
  static const cleaning = DeviceCategory('Temizlik', Icons.cleaning_services_outlined);
  static const electronics = DeviceCategory('Elektronik', Icons.devices_other_outlined);
  static const personalCare = DeviceCategory('Kişisel Bakım', Icons.spa_outlined);
  static const other = DeviceCategory('Diğer', Icons.category_outlined);

  static const all = [kitchen, climate, filters, cleaning, electronics, personalCare, other];

  /// Bilinmeyen veya boş kategori için genel cihaz simgesi döner.
  static IconData iconFor(String? label) {
    for (final category in all) {
      if (category.label == label) return category.icon;
    }
    return Icons.devices;
  }
}
