import 'package:intl/intl.dart';

/// "8.489 TL"; kuruş varsa "8.489,50 TL".
String formatPrice(double price) {
  final hasCents = (price * 100).round() % 100 != 0;
  return '${NumberFormat(hasCents ? '#,##0.00' : '#,##0', 'tr_TR').format(price)} TL';
}

/// Düzenleme alanındaki değer: "8489" ya da "8489,5" (binlik ayracı yok).
String priceToInput(double price) {
  if (price == price.roundToDouble()) return price.round().toString();
  return price.toString().replaceAll('.', ',');
}

/// "8.489,50", "8489,5", "8.489", "8489.5", "8489 TL" gibi girdileri okur; okunamazsa `null`.
double? parsePrice(String input) {
  var text = input.replaceAll(RegExp(r'\s|TL|₺', caseSensitive: false), '');
  if (text.isEmpty) return null;

  if (text.contains(',')) {
    text = text.replaceAll('.', '').replaceAll(',', '.');
  } else if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(text)) {
    text = text.replaceAll('.', ''); // 8.489 → 8489
  }

  final value = double.tryParse(text);
  return value == null || value < 0 ? null : value;
}

/// "4 Yıl 11 Ay", "3 Ay"; satın alma tarihi bir aydan yeniyse "1 Aydan az".
String usageTimeLabel(DateTime purchaseDate, DateTime now) {
  var years = now.year - purchaseDate.year;
  var months = now.month - purchaseDate.month;

  if (months < 0) {
    years--;
    months += 12;
  }

  if (years > 0 && months > 0) return '$years Yıl $months Ay';
  if (years > 0) return '$years Yıl';
  if (months > 0) return '$months Ay';
  return '1 Aydan az';
}

/// Garantiden kalan süre: "1 yıl 3 ay kaldı", "5 ay 12 gün kaldı", "9 gün kaldı". Bitiş bugünse
/// "Bugün sona eriyor", geçmişteyse "Süresi doldu".
String warrantyRemainingLabel(DateTime endDate, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final end = DateTime(endDate.year, endDate.month, endDate.day);
  if (end.isBefore(today)) return 'Süresi doldu';
  if (end == today) return 'Bugün sona eriyor';

  var months = (end.year - today.year) * 12 + end.month - today.month;
  if (end.day < today.day) months--;
  final anchor = DateTime(today.year, today.month + months, today.day);
  final days = end.difference(anchor).inDays;

  final years = months ~/ 12;
  final restMonths = months % 12;
  final parts = [
    if (years > 0) '$years yıl',
    if (restMonths > 0) '$restMonths ay',
    // Yıl da gösteriliyorsa gün ayrıntısı gereksiz uzatır.
    if (days > 0 && years == 0) '$days gün',
  ];
  return '${parts.join(' ')} kaldı';
}
