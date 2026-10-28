import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:homecare/data/models/history_model.dart';
import 'package:homecare/features/history/timeline.dart';

HistoryModel log(String task, DateTime at) {
  return HistoryModel()
    ..deviceName = 'Cihaz'
    ..taskName = task
    ..completedAt = at;
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  group('groupHistoryByDay', () {
    test('kayıtları takvim gününe göre gruplar, en yeni gün ve kayıt önce gelir', () {
      final groups = groupHistoryByDay([
        log('eski', DateTime(2026, 11, 14, 9, 0)),
        log('sabah', DateTime(2026, 11, 15, 8, 0)),
        log('akşam', DateTime(2026, 11, 15, 21, 30)),
        log('gece yarısı öncesi', DateTime(2026, 11, 15, 23, 59)),
      ]);

      expect(groups.map((g) => g.day), [DateTime(2026, 11, 15), DateTime(2026, 11, 14)]);
      expect(groups[0].entries.map((e) => e.taskName), ['gece yarısı öncesi', 'akşam', 'sabah']);
      expect(groups[1].entries.map((e) => e.taskName), ['eski']);
    });

    test('kayıt yoksa boş liste döner', () {
      expect(groupHistoryByDay(const []), isEmpty);
    });
  });

  group('timelineDayLabel', () {
    final now = DateTime(2026, 11, 15, 14, 0);

    test('bugün ve dün için özel etiket kullanır', () {
      expect(timelineDayLabel(DateTime(2026, 11, 15), now), 'Bugün');
      expect(timelineDayLabel(DateTime(2026, 11, 14), now), 'Dün');
    });

    test('ay başında dün bir önceki aya düşer', () {
      expect(timelineDayLabel(DateTime(2026, 10, 31), DateTime(2026, 11, 1, 10)), 'Dün');
    });

    test('aynı yıl için gün ve Türkçe ay adı yazar', () {
      expect(timelineDayLabel(DateTime(2026, 11, 3), now), '3 Kasım');
    });

    test('başka yıl için yılı da yazar', () {
      expect(timelineDayLabel(DateTime(2025, 12, 31), now), '31 Aralık 2025');
    });
  });
}
