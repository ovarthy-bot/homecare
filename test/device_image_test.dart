import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:homecare/core/services/device_image_service.dart';

void main() {
  const prefix = 'data:image/jpeg;base64,';
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('homecare_image_test'));
  tearDown(() => dir.delete(recursive: true));

  File writePng(String name, img.Image image) =>
      File('${dir.path}${Platform.pathSeparator}$name')..writeAsBytesSync(img.encodePng(image));

  img.Image gradient(int width, int height) {
    final image = img.Image(width: width, height: height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        image.setPixelRgb(x, y, x * 255 ~/ width, y * 255 ~/ height, 128);
      }
    }
    return image;
  }

  img.Image decode(String dataUrl) => img.decodeJpg(base64Decode(dataUrl.substring(prefix.length)))!;

  group('thumbnailDataUrl', () {
    test('en uzun kenarı 256 piksele indirir, oranı korur ve sınırın içinde kalır', () async {
      final file = writePng('wide.png', gradient(1200, 600));

      final url = (await DeviceImages.thumbnailDataUrl(file.path))!;

      expect(url, startsWith(prefix));
      expect(url.length, lessThanOrEqualTo(DeviceImages.maxDataUrlLength));
      final thumbnail = decode(url);
      expect([thumbnail.width, thumbnail.height], [256, 128]);
    });

    test('dik fotoğrafta yükseklik 256 olur', () async {
      final file = writePng('tall.png', gradient(300, 900));

      final thumbnail = decode((await DeviceImages.thumbnailDataUrl(file.path))!);

      expect([thumbnail.width, thumbnail.height], [85, 256]);
    });

    test('küçük fotoğrafı büyütmez', () async {
      final file = writePng('small.png', gradient(100, 80));

      final thumbnail = decode((await DeviceImages.thumbnailDataUrl(file.path))!);

      expect([thumbnail.width, thumbnail.height], [100, 80]);
    });

    test('çok ayrıntılı fotoğraf sığmazsa daha küçük ayarla yine sığdırılır', () async {
      final random = math.Random(7);
      final noise = img.Image(width: 1000, height: 1000);
      for (final pixel in noise) {
        pixel.setRgb(random.nextInt(256), random.nextInt(256), random.nextInt(256));
      }
      final file = writePng('noise.png', noise);

      final url = (await DeviceImages.thumbnailDataUrl(file.path))!;

      expect(url.length, lessThanOrEqualTo(DeviceImages.maxDataUrlLength));
      expect(decode(url).width, lessThan(256));
    });

    test('saydam PNG siyah değil, beyaz zemine konur', () async {
      final transparent = img.Image(width: 64, height: 64, numChannels: 4);
      final file = writePng('transparent.png', transparent);

      final thumbnail = decode((await DeviceImages.thumbnailDataUrl(file.path))!);

      expect(thumbnail.getPixel(32, 32).luminance, greaterThan(0.9 * 255));
    });

    test('resim olmayan dosya ve olmayan yol için null döner', () async {
      final junk = File('${dir.path}${Platform.pathSeparator}junk.jpg')..writeAsBytesSync([1, 2, 3]);

      expect(await DeviceImages.thumbnailDataUrl(junk.path), isNull);
      expect(await DeviceImages.thumbnailDataUrl('${dir.path}${Platform.pathSeparator}yok.jpg'), isNull);
    });
  });

  group('stampOf', () {
    test('dosya yoksa, yol boşsa ya da klasörse null döner', () async {
      expect(await DeviceImages.stampOf(null), isNull);
      expect(await DeviceImages.stampOf(''), isNull);
      expect(await DeviceImages.stampOf('${dir.path}${Platform.pathSeparator}yok.jpg'), isNull);
      expect(await DeviceImages.stampOf(dir.path), isNull);
    });

    test('dosya değişmedikçe aynı, değişince farklı olur', () async {
      final file = writePng('photo.png', gradient(40, 40));

      final first = await DeviceImages.stampOf(file.path);
      expect(first, isNotNull);
      expect(await DeviceImages.stampOf(file.path), first);

      file.writeAsBytesSync(img.encodePng(gradient(80, 80)));
      expect(await DeviceImages.stampOf(file.path), isNot(first));
    });
  });
}
