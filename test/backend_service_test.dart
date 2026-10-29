import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:homecare/core/services/backend_service.dart';
import 'package:homecare/data/models/device_model.dart';
import 'package:homecare/data/models/settings_model.dart';

import 'support/fake_backend.dart';
import 'support/test_devices.dart';

SettingsModel configured({String url = 'https://script.google.com/macros/s/abc/exec', String key = 'secret'}) {
  return SettingsModel()
    ..backendUrl = url
    ..syncKey = key;
}

http.Response jsonResponse(Object body, [int status = 200]) {
  return http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json; charset=utf-8'});
}

void main() {
  group('anahtarlar', () {
    test('cihaz anahtarı backend/apps-script testindeki vektörle aynıdır', () {
      // HMAC-SHA256("secret", "3") = 88a43b1b8ef6d2e900797363da21fd2bb29351d3022389feb31fb1340a94dae2
      expect(BackendService.deviceKey('secret', 3), '88a43b1b8ef6d2e9');
    });

    test('her cihaz için farklı, 16 haneli ve onaltılık', () {
      final keys = {for (var id = 1; id <= 50; id++) BackendService.deviceKey('secret', id)};

      expect(keys, hasLength(50));
      expect(keys.every((k) => RegExp(r'^[0-9a-f]{16}$').hasMatch(k)), isTrue);
    });

    test('gizli anahtar değişince cihaz anahtarı da değişir', () {
      expect(BackendService.deviceKey('baska', 3), isNot(BackendService.deviceKey('secret', 3)));
    });

    test('karekod anahtarı yalnızca ara depo kuruluysa üretilir', () {
      expect(BackendService.qrKeyFor(SettingsModel(), 3), isNull);
      expect(BackendService.qrKeyFor(SettingsModel()..backendUrl = 'https://x', 3), isNull);
      expect(BackendService.qrKeyFor(SettingsModel()..syncKey = 'secret', 3), isNull);
      expect(BackendService.qrKeyFor(configured(), 3), '88a43b1b8ef6d2e9');
    });

    test('adres ve anahtardaki boşluklar yok sayılır', () {
      expect(BackendService.qrKeyFor(configured(key: '  secret \n'), 3), '88a43b1b8ef6d2e9');
      expect(BackendService.isConfigured(configured(url: '   ')), isFalse);
    });
  });

  group('devicePayload', () {
    test('görev numaralarını ve UTC bakım tarihini taşır, boş alanları atar', () {
      final lastDone = DateTime.utc(2026, 10, 1, 8, 30);
      final done = taskOf(11, 'Kireç çözme', intervalDays: 60, completedDaysAgo: 0)..lastCompletedAt = lastDone.toLocal();
      final neverDone = taskOf(12, 'Hiç yapılmadı', intervalDays: 7, completedDaysAgo: 0)..lastCompletedAt = null;
      final device = TestDevice([done, neverDone])
        ..id = 3
        ..name = 'Philips Kahve Makinesi'
        ..room = 'Mutfak'
        ..category = 'Mutfak Aletleri'
        ..notes = ''
        ..serviceInfo = null;

      final payload = BackendService.devicePayload(device);

      expect(payload['id'], 3);
      expect(payload['category'], 'Mutfak Aletleri');
      expect(payload['warranty'], 24);
      expect(payload.containsKey('modelInfo'), isFalse);
      expect(payload.containsKey('price'), isFalse);
      expect(payload.containsKey('notes'), isFalse);
      expect(payload.containsKey('serviceInfo'), isFalse);
      expect(payload.containsKey('purchaseDate'), isFalse);

      final tasks = (payload['tasks'] as List).cast<Map<String, dynamic>>();
      expect(tasks.map((t) => t['id']), [11, 12]);
      expect(tasks[0]['lastCompletedAt'], '2026-10-01T08:30:00.000Z');
      expect(tasks[1].containsKey('lastCompletedAt'), isFalse);
    });
  });

  group('istekler', () {
    test('anahtar gövdede gider, adreste değil; içerik türü text/plain', () async {
      late http.Request seen;
      final service = BackendService(client: MockClient((request) async {
        seen = request;
        return jsonResponse({'ok': true});
      }));

      await service.ping(configured());

      expect(seen.method, 'POST');
      expect(seen.url.toString(), 'https://script.google.com/macros/s/abc/exec');
      expect(seen.headers['Content-Type'], startsWith('text/plain'));
      expect(jsonDecode(seen.body), {'action': 'ping', 'key': 'secret'});
    });

    test('POST yanıtını 302 yönlendirmesinin arkasından alır', () async {
      final fake = FakeBackend();
      fake.pending.add({
        'recordId': 'r1',
        'deviceId': 3,
        'taskId': 11,
        'taskName': 'Kireç çözme',
        'recordedAt': '2026-10-28T09:15:00.000Z',
      });

      final records = (await BackendService(client: fake.client).pull(configured())).records;

      expect(records, hasLength(1));
      expect(records.single.recordId, 'r1');
      expect(records.single.deviceId, 3);
      expect(records.single.taskId, 11);
      expect(records.single.taskName, 'Kireç çözme');
      expect(records.single.recordedAt.toUtc(), DateTime.utc(2026, 10, 28, 9, 15));
      expect(records.single.recordedAt.isUtc, isFalse, reason: 'ekranda yerel saat gösterilir');
    });

    test('Türkçe karakterler yönlendirmeden bozulmadan geçer', () async {
      final fake = FakeBackend();
      fake.pending.add({
        'recordId': 'r1',
        'deviceId': 1,
        'taskId': 1,
        'taskName': 'Çöp haznesi temizliği şığ',
        'recordedAt': '2026-10-28T09:15:00.000Z',
      });

      final records = (await BackendService(client: fake.client).pull(configured())).records;

      expect(records.single.taskName, 'Çöp haznesi temizliği şığ');
    });

    test('web\'de düzenlenen notları da çeker; not göndermeyen eski betikte liste boştur', () async {
      final fake = FakeBackend();
      fake.pendingNotes.add({
        'noteId': 'n1',
        'deviceId': 3,
        'text': 'Filtre: F-12 ğüşiöç',
        'editedAt': '2026-10-28T09:15:00.000Z',
      });

      final inbox = await BackendService(client: fake.client).pull(configured());

      expect(inbox.notes, hasLength(1));
      expect(inbox.notes.single.noteId, 'n1');
      expect(inbox.notes.single.deviceId, 3);
      expect(inbox.notes.single.text, 'Filtre: F-12 ğüşiöç');
      expect(inbox.notes.single.editedAt.toUtc(), DateTime.utc(2026, 10, 28, 9, 15));

      final oldScript = BackendService(client: MockClient((_) async => jsonResponse({'ok': true, 'records': []})));
      expect((await oldScript.pull(configured())).notes, isEmpty);
    });

    test('onay hem kayıt hem not numaralarını taşır', () async {
      final fake = FakeBackend();

      await BackendService(client: fake.client).acknowledge(configured(), ['r1'], noteIds: ['n1']);

      expect(fake.acknowledged, ['r1']);
      expect(fake.acknowledgedNotes, ['n1']);
    });

    test('yönlendirme yanıtında Location yoksa durum koduyla hata verir', () async {
      final service = BackendService(client: MockClient((_) async => http.Response('', 302)));

      expect(
        () => service.ping(configured()),
        throwsA(isA<BackendException>().having((e) => e.message, 'message', contains('302'))),
      );
    });

    test('yönlendirme döngüsüne girmez', () async {
      var calls = 0;
      final service = BackendService(client: MockClient((_) async {
        calls++;
        return http.Response('', 302, headers: {'location': 'https://example.com/again'});
      }));

      await expectLater(service.ping(configured()), throwsA(isA<BackendException>()));
      expect(calls, 4, reason: '1 POST + en fazla 3 yönlendirme');
    });

    test('201 cihaz iki istekte gönderilir', () async {
      final fake = FakeBackend();
      final devices = [
        for (var id = 1; id <= 201; id++)
          DeviceModel()
            ..id = id
            ..name = 'Cihaz $id'
            ..room = 'Oda',
      ];

      await BackendService(client: fake.client).pushDevices(configured(), devices);

      final batches = fake.requests.where((r) => r['action'] == 'putDevices').map((r) => (r['devices'] as List).length);
      expect(batches, [200, 1]);
      expect(fake.pushedDevices, hasLength(201));
    });

    test('onaylanacak kayıt yoksa istek atılmaz', () async {
      final fake = FakeBackend();

      await BackendService(client: fake.client).acknowledge(configured(), []);

      expect(fake.requests, isEmpty);
    });
  });

  group('hata mesajları', () {
    Future<BackendException> failureOf(http.Client client) async {
      try {
        await BackendService(client: client).ping(configured());
      } on BackendException catch (e) {
        return e;
      }
      fail('Hata bekleniyordu');
    }

    test('yanlış anahtar', () async {
      final fake = FakeBackend(secret: 'baska');

      final error = await failureOf(fake.client);

      expect(error.message, contains('SECRET ile aynı değil'));
    });

    test('ara depoda SECRET tanımlı değil', () async {
      final error = await failureOf(MockClient((_) async => jsonResponse({'ok': false, 'error': 'not_configured'})));

      expect(error.message, contains('SECRET tanımlı değil'));
    });

    test('Google giriş sayfası (HTML) dönerse yayın ayarını hatırlatır', () async {
      final error = await failureOf(MockClient((_) async => http.Response('<html>Sign in</html>', 200)));

      expect(error.message, contains('Herkes'));
    });

    test('sunucu hata kodu', () async {
      final error = await failureOf(MockClient((_) async => http.Response('x', 500)));

      expect(error.message, contains('500'));
    });

    test('ağ yok', () async {
      final error = await failureOf(MockClient((_) async => throw http.ClientException('Failed host lookup')));

      expect(error.message, contains('ulaşılamadı'));
    });
  });
}
