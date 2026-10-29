import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Cihaz fotoğrafının web sayfasında gösterilecek küçük kopyası.
///
/// Fotoğraf telefonda bir dosyadır; sayfa onu göremez. Bu yüzden ara depoya (backend/apps-script)
/// yalnızca küçük bir JPEG gider.
class DeviceImages {
  /// Ara depodaki hücre sınırı 50.000 karakterdir; Code.gs içindeki `MAX_IMAGE_LENGTH` ile aynı.
  static const maxDataUrlLength = 45000;

  /// Sığmazsa bir sonraki, daha küçük ve daha sıkıştırılmış ayar denenir.
  static const _steps = [
    (side: 256, quality: 72),
    (side: 192, quality: 60),
    (side: 128, quality: 50),
  ];

  /// Dosya değişince değişen kısa damga. Dosya yoksa ya da okunamıyorsa `null`.
  /// Ara depo aynı damgayı görürse küçük resmi yeniden istemez.
  static Future<String?> stampOf(String? path) async {
    if (path == null || path.isEmpty) return null;
    try {
      final stat = await File(path).stat();
      if (stat.type != FileSystemEntityType.file) return null;
      return '${stat.size}-${stat.modified.millisecondsSinceEpoch}';
    } on FileSystemException {
      return null;
    }
  }

  /// `data:image/jpeg;base64,...` biçiminde küçük resim; fotoğraf okunamıyor ya da hiçbir ayarda
  /// [maxDataUrlLength] içine sığmıyorsa `null`.
  static Future<String?> thumbnailDataUrl(String path) async {
    final Uint8List source;
    try {
      source = await File(path).readAsBytes();
    } on FileSystemException {
      return null;
    }

    for (final step in _steps) {
      final jpeg = await _encodeJpeg(source, step.side, step.quality);
      if (jpeg == null) return null;
      final url = 'data:image/jpeg;base64,${base64Encode(jpeg)}';
      if (url.length <= maxDataUrlLength) return url;
    }
    return null;
  }

  /// Çözme ve küçültme yerel kodekte (hızlı); yalnızca küçük sonuç JPEG'e çevrilir.
  static Future<Uint8List?> _encodeJpeg(Uint8List source, int side, int quality) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(source);
      descriptor = await ui.ImageDescriptor.encoded(buffer);

      // Büyütme yapılmaz; en uzun kenar [side]'a iner, oran korunur.
      final scale = math.min(1.0, side / math.max(descriptor.width, descriptor.height));
      codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (descriptor.width * scale).round()),
        targetHeight: math.max(1, (descriptor.height * scale).round()),
      );
      image = (await codec.getNextFrame()).image;

      final rgba = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      if (rgba == null) return null;

      final pixels = Uint8List.fromList(rgba.buffer.asUint8List());
      _flattenOnWhite(pixels);
      final flat = img.Image.fromBytes(
        width: image.width,
        height: image.height,
        bytes: pixels.buffer,
        numChannels: 4,
      );
      return Uint8List.fromList(img.encodeJpg(flat, quality: quality));
    } catch (e) {
      debugPrint('Cihaz resmi küçültülemedi: $e');
      return null;
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  /// JPEG saydamlığı bilmez; saydam PNG'ler siyaha dönmesin diye beyaz zemine karıştırılır.
  static void _flattenOnWhite(Uint8List rgba) {
    for (var i = 0; i < rgba.length; i += 4) {
      final alpha = rgba[i + 3];
      if (alpha == 255) continue;
      for (var channel = 0; channel < 3; channel++) {
        rgba[i + channel] = (rgba[i + channel] * alpha + 255 * (255 - alpha)) ~/ 255;
      }
      rgba[i + 3] = 255;
    }
  }
}
