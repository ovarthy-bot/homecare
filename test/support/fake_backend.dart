import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Apps Script ara deposunun bellekte çalışan taklidi.
///
/// Gerçeği gibi her POST'a 302 ile yanıt verir; sonuç `Location` adresindeki GET'tedir.
/// Böylece istemcinin yönlendirme işleyişi de sınanır.
class FakeBackend {
  final String secret;

  /// `pull` ile dönecek bekleyen kayıtlar (onaylananlar çıkarılır).
  final pending = <Map<String, dynamic>>[];
  final acknowledged = <String>[];

  /// `pull` ile dönecek, web'de düzenlenmiş notlar (onaylananlar çıkarılır).
  final pendingNotes = <Map<String, dynamic>>[];
  final acknowledgedNotes = <String>[];
  final pushedDevices = <Map<String, dynamic>>[];
  final deletedDevices = <int>[];
  final requests = <Map<String, dynamic>>[];

  bool failPull = false;
  bool failPush = false;

  /// Onay isteği yanıtlanır ama kaydedilmez (ağ kesintisi gibi): kayıtlar tekrar gelir.
  bool dropAcknowledgements = false;

  final _results = <String, String>{};

  FakeBackend({this.secret = 'secret'});

  late final http.Client client = MockClient((request) async {
    if (request.method == 'GET') {
      final body = _results[request.url.pathSegments.last] ?? '{"ok":false,"error":"expired"}';
      return http.Response.bytes(utf8.encode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    }

    final body = jsonDecode(request.body) as Map<String, dynamic>;
    requests.add(body);
    final id = '${_results.length}';
    _results[id] = jsonEncode(_handle(body));
    return http.Response('', 302, headers: {'location': 'https://script.googleusercontent.com/macros/echo/$id'});
  });

  Map<String, dynamic> _handle(Map<String, dynamic> body) {
    if (body['key'] != secret) return {'ok': false, 'error': 'forbidden'};

    switch (body['action']) {
      case 'ping':
        return {'ok': true};
      case 'pull':
        if (failPull) return {'ok': false, 'error': 'server_error'};
        return {
          'ok': true,
          'records': pending.where((r) => !acknowledged.contains(r['recordId'])).toList(),
          'notes': pendingNotes.where((n) => !acknowledgedNotes.contains(n['noteId'])).toList(),
        };
      case 'ack':
        final ids = ((body['ids'] as List?) ?? const []).cast<String>();
        final noteIds = ((body['noteIds'] as List?) ?? const []).cast<String>();
        if (!dropAcknowledgements) {
          acknowledged.addAll(ids);
          acknowledgedNotes.addAll(noteIds);
        }
        return {'ok': true, 'acknowledged': ids.length};
      case 'putDevices':
        if (failPush) return {'ok': false, 'error': 'server_error'};
        final devices = (body['devices'] as List).cast<Map<String, dynamic>>();
        pushedDevices.addAll(devices);
        return {'ok': true, 'stored': devices.length};
      case 'deleteDevice':
        deletedDevices.add(body['id'] as int);
        return {'ok': true, 'deleted': true};
      default:
        return {'ok': false, 'error': 'unknown_action'};
    }
  }

  /// En son gönderilen cihaz bilgisi (aynı cihaz birden çok kez gönderilmiş olabilir).
  Map<String, dynamic>? lastPushed(int deviceId) {
    for (final device in pushedDevices.reversed) {
      if (device['id'] == deviceId) return device;
    }
    return null;
  }
}
