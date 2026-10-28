import 'package:flutter_test/flutter_test.dart';
import 'package:homecare/core/deep_link/deep_link.dart';

void main() {
  group('DeepLink.parse', () {
    test('karekoda yazılan web adresi cihaz sayfasını gösterir ve geri çözülür', () {
      expect(
        DeepLink.qrData(42),
        'https://ovarthy-bot.github.io/homecare/device/index.html?id=42',
      );

      final link = DeepLink.parse(DeepLink.qrData(42));

      expect(link?.type, DeepLinkType.recordMaintenance);
      expect(link?.deviceId, 42);
      expect(link?.location, '/bakim/yapildi?cihaz=42');
    });

    test('cihaz anahtarı karekoda eklenir ve uygulama çözümlemesini bozmaz', () {
      final data = DeepLink.qrData(42, key: '88a43b1b8ef6d2e9');

      expect(data, 'https://ovarthy-bot.github.io/homecare/device/index.html?id=42&k=88a43b1b8ef6d2e9');
      expect(DeepLink.parse(data)?.deviceId, 42);
      expect(DeepLink.parse(data)?.type, DeepLinkType.recordMaintenance);
    });

    test('anahtarsız karekod eski biçimle aynıdır', () {
      expect(DeepLink.qrData(7), 'https://ovarthy-bot.github.io/homecare/device/index.html?id=7');
    });

    test('sayfadaki düğmenin uygulama bağlantısı geri çözülür', () {
      expect(DeepLink.maintenanceDoneLink(42), 'homecare://app/bakim/yapildi?cihaz=42');

      final link = DeepLink.parse(DeepLink.maintenanceDoneLink(42));

      expect(link?.type, DeepLinkType.recordMaintenance);
      expect(link?.deviceId, 42);
      expect(link?.location, '/bakim/yapildi?cihaz=42');
    });

    test('host olmadan yazılmış kısa biçimi de kabul eder', () {
      final link = DeepLink.parse('homecare://bakim/yapildi?cihaz=7');

      expect(link?.type, DeepLinkType.recordMaintenance);
      expect(link?.deviceId, 7);
    });

    test('web adresi, http ve büyük harfli host ile de çözülür', () {
      expect(DeepLink.parse('http://ovarthy-bot.github.io/homecare/device/index.html?id=3')?.deviceId, 3);
      expect(DeepLink.parse('https://Ovarthy-Bot.GitHub.io/homecare/device/index.html?id=3')?.deviceId, 3);
    });

    test('web adresinden bakım kaydı çözülür', () {
      final link = DeepLink.parse(
        'https://ovarthy-bot.github.io/homecare/device/index.html?id=3',
      );

      expect(link?.type, DeepLinkType.recordMaintenance);
      expect(link?.deviceId, 3);
    });

    test('homecare://device/<id> yalnızca cihaz detayını açar', () {
      final link = DeepLink.parse('homecare://device/5');

      expect(link?.type, DeepLinkType.openDevice);
      expect(link?.location, '/device/5');
    });

    test('baştaki ve sondaki boşlukları yok sayar', () {
      expect(DeepLink.parse('  ${DeepLink.maintenanceDoneLink(1)}\n')?.deviceId, 1);
    });

    test('geçersiz ya da yabancı bağlantılar için null döner', () {
      const rejected = [
        '',
        'merhaba',
        'https://example.com/homecare/device/index.html?id=3',
        'https://ovarthy-bot.github.io/baska-proje/device/index.html?id=3',
        'https://ovarthy-bot.github.io/homecare/device/index.html',
        'https://ovarthy-bot.github.io/homecare/device/index.html?id=abc',
        'otherapp://app/bakim/yapildi?cihaz=3',
        'homecare://app/bakim/yapildi',
        'homecare://app/bakim/yapildi?cihaz=abc',
        'homecare://app/bakim/yapildi?cihaz=0',
        'homecare://app/bakim/yapildi?cihaz=-4',
        'homecare://app/bakim/silindi?cihaz=3',
        'homecare://device/xyz',
      ];

      for (final raw in rejected) {
        expect(DeepLink.parse(raw), isNull, reason: raw);
      }
    });
  });
}
