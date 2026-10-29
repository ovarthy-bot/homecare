import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:homecare/data/models/device_model.dart';
import 'package:homecare/features/devices/device_details.dart';

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  group('formatPrice', () {
    test('binlik ayraçlı gösterir, kuruş yoksa yazmaz', () {
      expect(formatPrice(8489), '8.489 TL');
      expect(formatPrice(950), '950 TL');
    });

    test('kuruş varsa iki hane yazar', () {
      expect(formatPrice(8489.5), '8.489,50 TL');
    });
  });

  group('parsePrice', () {
    test('Türkçe ve düz biçimleri okur', () {
      expect(parsePrice('8489'), 8489);
      expect(parsePrice('8.489'), 8489);
      expect(parsePrice('8.489,50'), 8489.5);
      expect(parsePrice('8489,5'), 8489.5);
      expect(parsePrice('8489.5'), 8489.5);
      expect(parsePrice(' 8.489 TL '), 8489);
    });

    test('boş ya da geçersiz girdide null döner', () {
      expect(parsePrice(''), isNull);
      expect(parsePrice('   '), isNull);
      expect(parsePrice('12,3,4'), isNull);
      expect(parsePrice('abc'), isNull);
    });

    test('priceToInput ile gidiş dönüş tutarlıdır', () {
      expect(priceToInput(8489), '8489');
      expect(priceToInput(8489.5), '8489,5');
      expect(parsePrice(priceToInput(8489.5)), 8489.5);
    });
  });

  group('warrantyRemainingLabel', () {
    final now = DateTime(2026, 5, 10, 14, 30);

    test('yıl ve ay kalmışsa ikisini de yazar', () {
      expect(warrantyRemainingLabel(DateTime(2027, 8, 10), now), '1 yıl 3 ay kaldı');
    });

    test('bir yıldan azsa ay ve gün yazar', () {
      expect(warrantyRemainingLabel(DateTime(2026, 10, 22), now), '5 ay 12 gün kaldı');
    });

    test('bir aydan azsa yalnızca gün yazar', () {
      expect(warrantyRemainingLabel(DateTime(2026, 5, 19), now), '9 gün kaldı');
    });

    test('tam yıl dolduğunda gün göstermez', () {
      expect(warrantyRemainingLabel(DateTime(2028, 5, 10), now), '2 yıl kaldı');
    });

    test('bitiş bugünse ve geçmişteyse özel metin döner', () {
      expect(warrantyRemainingLabel(DateTime(2026, 5, 10), now), 'Bugün sona eriyor');
      expect(warrantyRemainingLabel(DateTime(2026, 5, 9), now), 'Süresi doldu');
    });
  });

  group('usageTimeLabel', () {
    test('yıl ve ay ayrı ayrı yazılır', () {
      final now = DateTime(2026, 10, 29);
      expect(usageTimeLabel(DateTime(2021, 11, 7), now), '4 Yıl 11 Ay');
      expect(usageTimeLabel(DateTime(2024, 10, 1), now), '2 Yıl');
      expect(usageTimeLabel(DateTime(2026, 7, 1), now), '3 Ay');
      expect(usageTimeLabel(DateTime(2026, 10, 15), now), '1 Aydan az');
    });
  });

  group('DeviceModel.warrantyEndDate', () {
    DeviceModel deviceOf(DateTime? purchase, int months) => DeviceModel()
      ..purchaseDate = purchase
      ..warrantyMonths = months;

    test('satın alma tarihine garanti ayını ekler', () {
      expect(deviceOf(DateTime(2021, 11, 7), 24).warrantyEndDate, DateTime(2023, 11, 7));
      expect(deviceOf(DateTime(2025, 12, 15), 3).warrantyEndDate, DateTime(2026, 3, 15));
    });

    test('ay sonlarında bir sonraki aya taşmaz', () {
      expect(deviceOf(DateTime(2025, 1, 31), 1).warrantyEndDate, DateTime(2025, 2, 28));
      expect(deviceOf(DateTime(2024, 2, 29), 12).warrantyEndDate, DateTime(2025, 2, 28));
    });

    test('satın alma tarihi yoksa null döner', () {
      expect(deviceOf(null, 24).warrantyEndDate, isNull);
    });
  });
}
