import 'package:intl/intl.dart';

import '../../data/models/history_model.dart';

/// Zaman çizelgesinde tek bir güne ait kayıtlar (en yeni önce).
class TimelineDay {
  final DateTime day;
  final List<HistoryModel> entries;

  const TimelineDay(this.day, this.entries);
}

/// Kayıtları yerel takvim gününe göre gruplar; günler ve günün kayıtları en yeniden eskiye sıralıdır.
List<TimelineDay> groupHistoryByDay(Iterable<HistoryModel> logs) {
  final sorted = logs.toList()..sort((a, b) => b.completedAt.compareTo(a.completedAt));

  final days = <TimelineDay>[];
  for (final log in sorted) {
    final at = log.completedAt;
    final day = DateTime(at.year, at.month, at.day);
    if (days.isEmpty || days.last.day != day) {
      days.add(TimelineDay(day, []));
    }
    days.last.entries.add(log);
  }
  return days;
}

/// "Bugün", "Dün", "15 Kasım" ya da başka bir yılsa "15 Kasım 2025".
/// `tr_TR` yerel verisi `initializeDateFormatting` ile yüklenmiş olmalıdır.
String timelineDayLabel(DateTime day, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  if (day == today) return 'Bugün';
  if (day == DateTime(today.year, today.month, today.day - 1)) return 'Dün';
  return DateFormat(day.year == today.year ? 'd MMMM' : 'd MMMM y', 'tr_TR').format(day);
}
