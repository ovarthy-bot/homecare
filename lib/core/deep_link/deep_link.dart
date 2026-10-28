/// Cihaz karekodlarında taşınan bağlantıların üretimi ve çözümlenmesi.
///
/// Karekod bir web adresi taşır ([qrData]). Telefonun kamerası bunu cihaz sayfası olarak
/// açar; sayfadaki düğme [maintenanceDoneLink] ile uygulamayı açar. Uygulamanın kendi
/// tarayıcısı ve App Link olarak gelen adres doğrudan bakım kaydına gider.
///
/// `homecare://` bağlantısının yolu (`/bakim/yapildi`) host'tan bağımsız olarak uygulama
/// içi rotayla aynıdır; böylece işletim sistemi host'u düşürse bile doğru ekrana gider.
enum DeepLinkType {
  /// Cihazın bakımını, kullanıcıya soru sormadan kaydet.
  recordMaintenance,

  /// Yalnızca cihaz detayını aç.
  openDevice,
}

class DeepLink {
  final DeepLinkType type;
  final int deviceId;

  const DeepLink(this.type, this.deviceId);

  static const String scheme = 'homecare';

  /// Cihaz sayfasının yayınlandığı GitHub Pages adresi.
  static const String webHost = 'ovarthy-bot.github.io';

  /// Karekoda yazılan adres. Uygulaması olmayan telefonda da cihaz sayfası açılır.
  ///
  /// [key] ara depo kuruluysa o cihaza özel anahtardır (`BackendService.deviceKey`); sayfa bununla
  /// cihaz bilgisini okur ve bakım kaydı bırakır. Anahtarsız karekod yalnızca bilgi gösterir.
  static String qrData(int deviceId, {String? key}) {
    final base = 'https://$webHost/homecare/device/index.html?id=$deviceId';
    return key == null ? base : '$base&k=$key';
  }

  /// Uygulamayı doğrudan açıp bakımı kaydeden bağlantı (cihaz sayfasındaki düğme kullanır).
  static String maintenanceDoneLink(int deviceId) =>
      '$scheme://app/bakim/yapildi?cihaz=$deviceId';

  /// Uygulama içi rota.
  String get location => switch (type) {
        DeepLinkType.recordMaintenance => '/bakim/yapildi?cihaz=$deviceId',
        DeepLinkType.openDevice => '/device/$deviceId',
      };

  static DeepLink? parse(String raw) {
    final uri = Uri.tryParse(raw.trim());
    return uri == null ? null : parseUri(uri);
  }

  /// Tanınmayan her bağlantı için `null` döner.
  static DeepLink? parseUri(Uri uri) {
    switch (uri.scheme.toLowerCase()) {
      case scheme:
        return _parseAppLink(uri);
      case 'https':
      case 'http':
        return _parseWebLink(uri);
      default:
        return null;
    }
  }

  static DeepLink? _parseAppLink(Uri uri) {
    // `homecare://bakim/yapildi` (host = bakim) ile
    // `homecare://app/bakim/yapildi` aynı yola indirgenir.
    final segments = <String>[
      if (uri.host.isNotEmpty && uri.host != 'app') uri.host,
      ...uri.pathSegments,
    ].where((s) => s.isNotEmpty).toList();

    if (segments.length == 2 && segments[0] == 'bakim' && segments[1] == 'yapildi') {
      final id = _positiveInt(uri.queryParameters['cihaz']);
      return id == null ? null : DeepLink(DeepLinkType.recordMaintenance, id);
    }
    if (segments.length == 2 && segments[0] == 'device') {
      final id = _positiveInt(segments[1]);
      return id == null ? null : DeepLink(DeepLinkType.openDevice, id);
    }
    return null;
  }

  static DeepLink? _parseWebLink(Uri uri) {
    if (uri.host.toLowerCase() != webHost) return null;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length < 2 || segments[0] != 'homecare' || segments[1] != 'device') {
      return null;
    }
    // .../device/index.html?id=3
    final id = _positiveInt(uri.queryParameters['id']);
    return id == null ? null : DeepLink(DeepLinkType.recordMaintenance, id);
  }

  static int? _positiveInt(String? value) {
    final id = int.tryParse(value ?? '');
    return id != null && id > 0 ? id : null;
  }
}
