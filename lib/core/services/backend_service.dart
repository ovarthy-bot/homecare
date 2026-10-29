import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../../data/models/device_model.dart';
import '../../data/models/settings_model.dart';

/// Ara deponun (backend/apps-script/Code.gs) bildirdiği ya da erişimi engelleyen hata.
class BackendException implements Exception {
  final String message;

  const BackendException(this.message);

  @override
  String toString() => message;
}

/// Uygulaması olmayan bir telefondan web sayfasıyla bırakılmış bakım kaydı.
class WebRecord {
  final String recordId;
  final int deviceId;
  final int taskId;
  final String taskName;
  final DateTime recordedAt;

  const WebRecord({
    required this.recordId,
    required this.deviceId,
    required this.taskId,
    required this.taskName,
    required this.recordedAt,
  });
}

/// Web sayfasında düzenlenmiş, telefonun henüz almadığı cihaz notu.
class WebNote {
  final String noteId;
  final int deviceId;

  /// Boş metin, notun web'den silindiği anlamına gelir.
  final String text;
  final DateTime editedAt;

  const WebNote({
    required this.noteId,
    required this.deviceId,
    required this.text,
    required this.editedAt,
  });
}

/// Ara depoda telefonu bekleyen her şey.
class WebInbox {
  final List<WebRecord> records;
  final List<WebNote> notes;

  const WebInbox({required this.records, required this.notes});
}

/// [IsarService.syncWithBackend] sonucu.
class WebSyncResult {
  /// Telefona eklenen web kayıtları.
  final int imported;

  /// Web'den değiştirilip telefona alınan cihaz notları.
  final int notesUpdated;

  /// Bu telefonda karşılığı olmayan (cihaz ya da görev silinmiş) ve atlanan kayıtlar.
  final int unmatched;

  /// Ara depoya gönderilen cihaz sayısı.
  final int pushedDevices;

  /// Cihazlar gönderilemediyse nedeni; kayıtlar yine de alınmıştır.
  final String? pushError;

  const WebSyncResult({
    required this.imported,
    this.notesUpdated = 0,
    required this.unmatched,
    required this.pushedDevices,
    this.pushError,
  });

  /// Kullanıcıya gösterilecek tek satırlık özet.
  String get summary => [
        imported == 0 ? 'Yeni web kaydı yok' : '$imported web kaydı eklendi',
        if (notesUpdated > 0) '$notesUpdated not güncellendi',
        if (unmatched > 0) '$unmatched kayıt eşleşmedi (cihaz silinmiş olabilir)',
        pushError == null ? '$pushedDevices cihaz güncellendi' : 'cihazlar gönderilemedi: $pushError',
      ].join(' · ');
}

class BackendService {
  static const _timeout = Duration(seconds: 25);
  static const _maxDevicesPerRequest = 200;

  final http.Client _client;

  BackendService({http.Client? client}) : _client = client ?? http.Client();

  static bool isConfigured(SettingsModel settings) =>
      (settings.backendUrl ?? '').trim().isNotEmpty && (settings.syncKey ?? '').trim().isNotEmpty;

  /// Karekoda yazılan, yalnızca bu cihaza ait anahtar: HMAC-SHA256(syncKey, cihaz numarası)'nın
  /// ilk 16 hanesi. Code.gs içindeki `deviceKey_` ile aynı olmalıdır.
  static String deviceKey(String syncKey, int deviceId) {
    final digest = Hmac(sha256, utf8.encode(syncKey)).convert(utf8.encode('$deviceId'));
    return digest.toString().substring(0, 16);
  }

  /// Ara depo kurulu değilse `null`; karekod o zaman anahtarsız (eski) biçimde yazılır.
  static String? qrKeyFor(SettingsModel settings, int deviceId) =>
      isConfigured(settings) ? deviceKey(settings.syncKey!.trim(), deviceId) : null;

  /// [imageStamp]: cihaz fotoğrafının dosya damgası (`DeviceImages.stampOf`). Ara depo bunu
  /// saklananla karşılaştırıp küçük resmi gerekirse ister.
  static Map<String, dynamic> devicePayload(DeviceModel device, {String? imageStamp}) => {
        'id': device.id,
        'name': device.name,
        'room': device.room,
        if (device.category?.isNotEmpty ?? false) 'category': device.category,
        if (device.modelInfo?.isNotEmpty ?? false) 'modelInfo': device.modelInfo,
        if (device.price != null) 'price': device.price,
        'warranty': device.warrantyMonths,
        if (device.purchaseDate != null) 'purchaseDate': device.purchaseDate!.toIso8601String(),
        if (device.serviceInfo?.isNotEmpty ?? false) 'serviceInfo': device.serviceInfo,
        if (device.notes?.isNotEmpty ?? false) 'notes': device.notes,
        'imageStamp': ?imageStamp,
        'tasks': [
          for (final task in device.tasks)
            {
              'id': task.id,
              'name': task.name,
              'intervalDays': task.intervalDays,
              if (task.lastCompletedAt != null) 'lastCompletedAt': task.lastCompletedAt!.toUtc().toIso8601String(),
            },
        ],
      };

  /// Adres ve anahtarın doğru olup olmadığını sınar.
  Future<void> ping(SettingsModel settings) => _call(settings, {'action': 'ping'});

  /// Cihazları ara depoya yazar (varsa günceller). Görevlerin yüklü olması gerekir.
  ///
  /// [imageStamps] fotoğrafı olan cihazların dosya damgalarıdır. Dönen kümede, ara deponun küçük
  /// resmini istediği (yeni ya da değişmiş fotoğraflı) cihaz numaraları vardır; [putImage] ile yüklenir.
  /// Resim desteği olmayan eski bir betik `needImage` göndermez; o zaman küme boştur.
  Future<Set<int>> pushDevices(
    SettingsModel settings,
    List<DeviceModel> devices, {
    Map<int, String> imageStamps = const {},
  }) async {
    final needImage = <int>{};
    for (var start = 0; start < devices.length; start += _maxDevicesPerRequest) {
      final chunk = devices.skip(start).take(_maxDevicesPerRequest);
      final data = await _call(settings, {
        'action': 'putDevices',
        'devices': [for (final device in chunk) devicePayload(device, imageStamp: imageStamps[device.id])],
      });
      needImage.addAll([for (final id in (data['needImage'] as List? ?? const [])) (id as num).toInt()]);
    }
    return needImage;
  }

  /// Cihaz fotoğrafının küçük kopyasını (`data:image/jpeg;base64,...`) ara depoya yazar.
  Future<void> putImage(SettingsModel settings, int deviceId, String dataUrl, String stamp) =>
      _call(settings, {'action': 'putImage', 'id': deviceId, 'image': dataUrl, 'stamp': stamp});

  Future<void> deleteDevice(SettingsModel settings, int deviceId) =>
      _call(settings, {'action': 'deleteDevice', 'id': deviceId});

  /// Henüz içe aktarılmamış (bekleyen) kayıtlar eskiden yeniye, ve web'de düzenlenmiş notlar.
  /// Notları desteklemeyen eski bir betik `notes` göndermez; o zaman not listesi boştur.
  Future<WebInbox> pull(SettingsModel settings) async {
    final data = await _call(settings, {'action': 'pull'});
    return WebInbox(
      records: [
        for (final raw in (data['records'] as List? ?? const []))
          WebRecord(
            recordId: raw['recordId'] as String,
            deviceId: (raw['deviceId'] as num).toInt(),
            taskId: (raw['taskId'] as num).toInt(),
            taskName: raw['taskName'] as String,
            recordedAt: DateTime.parse(raw['recordedAt'] as String).toLocal(),
          ),
      ],
      notes: [
        for (final raw in (data['notes'] as List? ?? const []))
          WebNote(
            noteId: raw['noteId'] as String,
            deviceId: (raw['deviceId'] as num).toInt(),
            text: raw['text'] as String,
            editedAt: DateTime.parse(raw['editedAt'] as String).toLocal(),
          ),
      ],
    );
  }

  /// İçe aktarılan kayıt ve notları ara depoda "alındı" yapar; bir daha çekilmez.
  Future<void> acknowledge(SettingsModel settings, List<String> recordIds, {List<String> noteIds = const []}) async {
    if (recordIds.isEmpty && noteIds.isEmpty) return;
    await _call(settings, {
      'action': 'ack',
      if (recordIds.isNotEmpty) 'ids': recordIds,
      if (noteIds.isNotEmpty) 'noteIds': noteIds,
    });
  }

  /// Her çağrı POST'tur (anahtar adreste, günlüklerde kalmasın). Apps Script yanıtı bir
  /// yönlendirmenin arkasından verir: işlem ilk istekte yapılır, sonuç `Location` adresindedir.
  Future<Map<String, dynamic>> _call(SettingsModel settings, Map<String, dynamic> body) async {
    final url = Uri.parse((settings.backendUrl ?? '').trim());
    final payload = jsonEncode({...body, 'key': (settings.syncKey ?? '').trim()});

    try {
      var response = await _client
          .post(url, headers: {'Content-Type': 'text/plain; charset=utf-8'}, body: payload)
          .timeout(_timeout);

      for (var hops = 0; hops < 3 && _isRedirect(response.statusCode); hops++) {
        final location = response.headers['location'];
        if (location == null) break;
        response = await _client.get(url.resolve(location)).timeout(_timeout);
      }

      if (response.statusCode != 200) {
        throw BackendException('Ara depo ${response.statusCode} koduyla yanıt verdi.');
      }

      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map<String, dynamic>) throw const FormatException();
      if (data['ok'] != true) throw BackendException(_describe(data['error']));
      return data;
    } on BackendException {
      rethrow;
    } on TimeoutException {
      throw const BackendException('Ara depo zamanında yanıt vermedi.');
    } on FormatException {
      // Genellikle web uygulaması "Herkes" erişimiyle yayınlanmadığında Google bir giriş sayfası döndürür.
      throw const BackendException(
        'Ara depodan beklenmeyen yanıt geldi. Web uygulamasının "Erişimi olan: Herkes" ile yayınlandığından emin olun.',
      );
    } on Exception {
      // ClientException, SocketException, TLS hataları...: hepsi "ulaşılamadı".
      throw const BackendException('Ara depoya ulaşılamadı. İnternet bağlantısını kontrol edin.');
    }
  }

  static bool _isRedirect(int status) => status == 301 || status == 302 || status == 303 || status == 307 || status == 308;

  static String _describe(Object? code) => switch (code) {
        'forbidden' => 'Eşitleme anahtarı, ara depodaki SECRET ile aynı değil.',
        'not_configured' => 'Ara depoda SECRET tanımlı değil. Kurulum adımlarını kontrol edin.',
        'too_many_devices' => 'Tek seferde çok fazla cihaz gönderildi.',
        _ => 'Ara depo hata döndürdü ($code).',
      };
}
