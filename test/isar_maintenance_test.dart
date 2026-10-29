// Gerçek Isar ile karekod bakım kaydını sınar. Yalnızca Windows'ta ve paketle gelen
// isar.dll bulunabiliyorsa çalışır; veritabanı geçici bir klasörde açılır.
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:isar/isar.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:homecare/core/services/backend_service.dart';
import 'package:homecare/data/local/isar_service.dart';
import 'package:homecare/data/models/device_model.dart';
import 'package:homecare/data/models/history_model.dart';
import 'package:homecare/data/models/maintenance_receipt.dart';
import 'package:homecare/data/models/task_model.dart';

import 'support/fake_backend.dart';

class _FakePathProvider extends PathProviderPlatform {
  final String documentsPath;

  _FakePathProvider(this.documentsPath);

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}

String? isarLibraryPath() {
  if (!Platform.isWindows) return null;
  final config = File('.dart_tool/package_config.json');
  if (!config.existsSync()) return null;

  final packages = (jsonDecode(config.readAsStringSync())['packages'] as List).cast<Map<String, dynamic>>();
  final libs = packages.where((p) => p['name'] == 'isar_flutter_libs');
  if (libs.isEmpty) return null;

  final root = config.absolute.uri.resolve(libs.first['rootUri'] as String).toFilePath();
  final dll = File('$root${Platform.pathSeparator}windows${Platform.pathSeparator}isar.dll');
  return dll.existsSync() ? dll.path : null;
}

Future<void> eventually(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Koşul 5 saniyede sağlanmadı');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  final library = isarLibraryPath();

  group('IsarService karekodla bakım kaydı', skip: library == null ? 'Isar yerel kütüphanesi bulunamadı' : null, () {
    late Directory tempDir;
    late IsarService service;
    late Isar isar;

    setUpAll(() async {
      await Isar.initializeIsarCore(libraries: {Abi.windowsX64: library!});
      tempDir = await Directory.systemTemp.createTemp('homecare_isar_test');
      PathProviderPlatform.instance = _FakePathProvider(tempDir.path);

      service = IsarService();
      isar = await service.db; // boşsa örnek verileri ekler
    });

    tearDownAll(() async {
      await isar.close();
      await tempDir.delete(recursive: true);
    });

    Future<DeviceModel> deviceNamed(String name) async {
      final device = (await service.getDevices()).firstWhere((d) => d.name == name);
      return (await service.getDeviceById(device.id))!;
    }

    Future<List<HistoryModel>> historyOf(int deviceId) async {
      return isar.historyModels.filter().deviceIdEqualTo(deviceId).findAll();
    }

    Future<void> setLastCompleted(TaskModel task, DateTime at) async {
      task.lastCompletedAt = at;
      await isar.writeTxn(() => isar.taskModels.put(task));
    }

    test('birden fazla görevi olan cihazda hiçbir şey kaydetmeden seçim ister; seçilenler kaydedilir ve geri alınır',
        () async {
      final philips = await deviceNamed('Philips Kahve Makinesi');
      final before = {for (final t in philips.tasks) t.id: t.lastCompletedAt};
      final startedAt = DateTime.now();

      final prompt = (await service.recordMaintenanceViaQr(philips.id))!;

      expect(prompt.outcome, MaintenanceOutcome.needsSelection);
      expect(prompt.deviceName, 'Philips Kahve Makinesi');
      expect(await historyOf(philips.id), isEmpty, reason: 'seçim yapılmadan kayıt açılmamalı');

      final chosen = philips.tasks.where((t) => t.name != 'Kireç çözme').map((t) => t.id).toSet();
      final receipt = (await service.recordSelectedTasks(philips.id, chosen))!;

      expect(receipt.outcome, MaintenanceOutcome.recorded);
      expect(receipt.taskNames, unorderedEquals(['Çöp haznesi temizliği', 'Demlik temizliği']));

      final history = await historyOf(philips.id);
      expect(history, hasLength(2));
      expect(history.every((h) => h.deviceName == 'Philips Kahve Makinesi'), isTrue);

      final limescale = philips.tasks.firstWhere((t) => t.name == 'Kireç çözme');
      expect((await isar.taskModels.get(limescale.id))!.lastCompletedAt!.isAtSameMomentAs(before[limescale.id]!), isTrue,
          reason: 'seçilmeyen göreve dokunulmamalı');
      final recordedTask = (await isar.taskModels.get(receipt.recorded.first.taskId))!;
      expect(recordedTask.lastCompletedAt!.isBefore(startedAt), isFalse);

      await service.undoMaintenance(receipt);

      expect(await historyOf(philips.id), isEmpty);
      final restored = await deviceNamed('Philips Kahve Makinesi');
      for (final t in restored.tasks) {
        expect(t.lastCompletedAt!.isAtSameMomentAs(before[t.id]!), isTrue, reason: t.name);
      }
    });

    test('yalnızca seçilen görevi kaydeder; cihaza ait olmayan görev numaralarını yok sayar', () async {
      final epson = await deviceNamed('Epson Yazıcı');
      final selected = epson.tasks.firstWhere((t) => t.name == 'Yazıcı kartuş temizleme');
      final untouched = epson.tasks.firstWhere((t) => t.name == 'Kartuş kafası hizalama');
      await setLastCompleted(selected, DateTime.now().subtract(const Duration(days: 40)));
      final untouchedBefore = (await isar.taskModels.get(untouched.id))!.lastCompletedAt!;
      final foreignTaskId = (await deviceNamed('Daikin Klima')).tasks.single.id;

      final receipt = (await service.recordSelectedTasks(epson.id, {selected.id, foreignTaskId}))!;

      expect(receipt.taskNames, ['Yazıcı kartuş temizleme']);
      expect((await isar.taskModels.get(selected.id))!.daysRemaining, 30);
      expect((await isar.taskModels.get(untouched.id))!.lastCompletedAt!.isAtSameMomentAs(untouchedBefore), isTrue);
      expect(await historyOf(epson.id), hasLength(1));
    });

    test('boş seçim kayıt açmaz', () async {
      final xiaomi = await deviceNamed('Xiaomi Mop Pro Robot Süpürge');
      final before = (await historyOf(xiaomi.id)).length;

      final receipt = (await service.recordSelectedTasks(xiaomi.id, {}))!;

      expect(receipt.outcome, MaintenanceOutcome.noTasks);
      expect(await historyOf(xiaomi.id), hasLength(before));
    });

    test('tek görevli cihazda okutma, görevin zamanı gelmemiş olsa da soru sormadan kaydeder', () async {
      final daikin = await deviceNamed('Daikin Klima');
      expect(daikin.tasks, hasLength(1));
      expect(daikin.tasks.single.daysRemaining, greaterThan(0));

      final receipt = (await service.recordMaintenanceViaQr(daikin.id))!;

      expect(receipt.outcome, MaintenanceOutcome.recorded);
      expect(receipt.taskNames, ['Filtre temizliği']);
      expect(await historyOf(daikin.id), hasLength(1));

      await service.undoMaintenance(receipt);
      expect(await historyOf(daikin.id), isEmpty);
    });

    test('kısa süre içinde gelen ikinci okutma yeni kayıt açmaz', () async {
      final daikin = await deviceNamed('Daikin Klima');

      final first = (await service.recordMaintenanceViaQr(daikin.id))!;
      final second = (await service.recordMaintenanceViaQr(daikin.id))!;

      expect(first.outcome, MaintenanceOutcome.recorded);
      expect(second.outcome, MaintenanceOutcome.alreadyRecorded);
      expect(second.taskNames, first.taskNames);
      expect(second.canUndo, isFalse);
      expect(await historyOf(daikin.id), hasLength(1));
    });

    test('tekrar koruma penceresi dışındaki okutma yeni kayıt açar', () async {
      final oralB = await deviceNamed('Oral-B Şarjlı Diş Fırçası');

      await service.recordMaintenanceViaQr(oralB.id);
      final again = (await service.recordMaintenanceViaQr(oralB.id, duplicateWindow: Duration.zero))!;

      expect(again.outcome, MaintenanceOutcome.recorded);
      expect(await historyOf(oralB.id), hasLength(2));
    });

    test('görevi olmayan cihazda kayıt açmaz', () async {
      final empty = DeviceModel()
        ..name = 'Görevsiz Cihaz'
        ..room = 'Salon';
      await service.saveDeviceWithTasks(empty, []);

      final receipt = (await service.recordMaintenanceViaQr(empty.id))!;

      expect(receipt.outcome, MaintenanceOutcome.noTasks);
      expect(await historyOf(empty.id), isEmpty);
    });

    test('olmayan cihaz için null döner', () async {
      expect(await service.recordMaintenanceViaQr(999999), isNull);
    });

    test('cihaz listesi akışı görev değişince de yeniden yayılır', () async {
      final xiaomi = await deviceNamed('Xiaomi Mop Pro Robot Süpürge');
      final emissions = <List<DeviceModel>>[];
      final subscription = service.listenToDevices().listen(emissions.add);

      await eventually(() => emissions.isNotEmpty);
      final seen = emissions.length;

      final receipt = (await service.recordSelectedTasks(xiaomi.id, {xiaomi.tasks.first.id}))!;
      await eventually(() => emissions.length > seen);

      final latest = emissions.last.firstWhere((d) => d.id == xiaomi.id);
      final task = latest.tasks.firstWhere((t) => t.id == receipt.recorded.single.taskId);
      expect(task.lastCompletedAt!.isAtSameMomentAs(receipt.recorded.single.nextDueDate.subtract(Duration(days: task.intervalDays))), isTrue);

      await subscription.cancel();
    });

    test('kategori kaydedilir ve dışa/içe aktarmadan geçer', () async {
      final philips = await deviceNamed('Philips Kahve Makinesi');
      expect(philips.category, 'Mutfak Aletleri');

      await service.importDataFromJson(jsonEncode({
        'devices': [
          {'name': 'İçe Aktarılan', 'room': 'Banyo', 'category': 'Filtre & Arıtma', 'tasks': []},
        ],
      }));

      final imported = await deviceNamed('İçe Aktarılan');
      expect(imported.category, 'Filtre & Arıtma');
    });

    group('web kayıtları (ara depo)', () {
      late FakeBackend backend;
      late IsarService webService;

      Future<void> configure({required bool enabled}) async {
        final settings = await service.getSettings();
        settings.backendUrl = enabled ? 'https://script.google.com/macros/s/abc/exec' : null;
        settings.syncKey = enabled ? 'secret' : null;
        await service.updateSettings(settings);
      }

      Map<String, dynamic> webRecord(String id, DeviceModel device, TaskModel task, DateTime at) => {
            'recordId': id,
            'deviceId': device.id,
            'taskId': task.id,
            'taskName': 'ara depodaki eski ad',
            'recordedAt': at.toUtc().toIso8601String(),
          };

      setUp(() async {
        backend = FakeBackend();
        // Aynı Isar örneğini paylaşır; yalnızca ara depo istemcisi sahtedir.
        webService = IsarService(backend: BackendService(client: backend.client));
        await configure(enabled: true);
      });

      tearDown(() => configure(enabled: false));

      test('bekleyen kayıtları telefona alır, onaylar ve güncel cihazları gönderir', () async {
        final epson = await deviceNamed('Epson Yazıcı');
        final task = epson.tasks.firstWhere((t) => t.name == 'Kartuş kafası hizalama');
        final recordedAt = DateTime.now().add(const Duration(minutes: 1));
        backend.pending.addAll([
          webRecord('r1', epson, task, recordedAt),
          {'recordId': 'r2', 'deviceId': 999999, 'taskId': 1, 'taskName': 'silinmiş', 'recordedAt': recordedAt.toUtc().toIso8601String()},
        ]);

        final result = (await webService.syncWithBackend())!;

        expect(result.imported, 1);
        expect(result.unmatched, 1, reason: 'cihazı olmayan kayıt atlanır');
        expect(result.pushError, isNull);

        final history = await isar.historyModels.filter().externalIdEqualTo('r1').findAll();
        expect(history, hasLength(1));
        expect(history.single.source, 'web');
        expect(history.single.deviceId, epson.id);
        expect(history.single.deviceName, 'Epson Yazıcı');
        expect(history.single.taskName, 'Kartuş kafası hizalama', reason: 'ad ara depodan değil telefondan gelir');
        expect(history.single.completedAt.isAtSameMomentAs(recordedAt), isTrue);
        expect(await isar.historyModels.filter().externalIdEqualTo('r2').findAll(), isEmpty);

        final updated = (await isar.taskModels.get(task.id))!;
        expect(updated.lastCompletedAt!.isAtSameMomentAs(recordedAt), isTrue);

        expect(backend.acknowledged, unorderedEquals(['r1', 'r2']), reason: 'karşılığı olmayan kayıt da onaylanır');

        final pushed = backend.lastPushed(epson.id)!;
        final pushedTask = (pushed['tasks'] as List).cast<Map<String, dynamic>>().firstWhere((t) => t['id'] == task.id);
        expect(DateTime.parse(pushedTask['lastCompletedAt'] as String).isAtSameMomentAs(recordedAt), isTrue,
            reason: 'web sayfası güncel bakım tarihini görmeli');
        expect(result.pushedDevices, greaterThanOrEqualTo(5));
      });

      test('onayı gidememiş kayıt ikinci eşitlemede tekrar eklenmez', () async {
        final oralB = await deviceNamed('Oral-B Şarjlı Diş Fırçası');
        backend.dropAcknowledgements = true;
        backend.pending.add(webRecord('dup1', oralB, oralB.tasks.single, DateTime.now()));

        final first = (await webService.syncWithBackend())!;
        final second = (await webService.syncWithBackend())!;

        expect(first.imported, 1);
        expect(second.imported, 0);
        expect(second.unmatched, 0);
        expect(await isar.historyModels.filter().externalIdEqualTo('dup1').findAll(), hasLength(1));
      });

      test('telefondaki daha yeni bakım tarihini eski web kaydıyla geri almaz', () async {
        final daikin = await deviceNamed('Daikin Klima');
        final task = daikin.tasks.single;
        final newer = DateTime.now();
        await setLastCompleted(task, newer);
        backend.pending.add(webRecord('old1', daikin, task, newer.subtract(const Duration(days: 3))));

        final result = (await webService.syncWithBackend())!;

        expect(result.imported, 1, reason: 'geçmişe yine de eklenir');
        expect((await isar.taskModels.get(task.id))!.lastCompletedAt!.isAtSameMomentAs(newer), isTrue);
      });

      test('ara depo kurulu değilse hiçbir istek atılmaz', () async {
        await configure(enabled: false);

        expect(await webService.syncWithBackend(), isNull);
        expect(backend.requests, isEmpty);
      });

      test('kayıtlar çekilemezse hata verir; hiçbir şey eklenmez ya da onaylanmaz', () async {
        final epson = await deviceNamed('Epson Yazıcı');
        backend.failPull = true;
        backend.pending.add(webRecord('fail1', epson, epson.tasks.first, DateTime.now()));

        await expectLater(webService.syncWithBackend(), throwsA(isA<BackendException>()));

        expect(backend.acknowledged, isEmpty);
        expect(await isar.historyModels.filter().externalIdEqualTo('fail1').findAll(), isEmpty);
      });

      test('cihazlar gönderilemese de alınan kayıtlar korunur ve onaylanır', () async {
        final epson = await deviceNamed('Epson Yazıcı');
        backend.failPush = true;
        backend.pending.add(webRecord('keep1', epson, epson.tasks.first, DateTime.now().add(const Duration(minutes: 2))));

        final result = (await webService.syncWithBackend())!;

        expect(result.imported, 1);
        expect(result.pushedDevices, 0);
        expect(result.pushError, isNotNull);
        expect(backend.acknowledged, contains('keep1'));
      });

      test('cihaz kaydedilince ve silinince ara depo güncellenir', () async {
        final device = DeviceModel()
          ..name = 'Web Test Cihazı'
          ..room = 'Salon'
          ..category = 'Diğer';
        final task = TaskModel()
          ..name = 'Filtre'
          ..intervalDays = 30
          ..lastCompletedAt = DateTime.now();

        await webService.saveDeviceWithTasks(device, [task]);
        await eventually(() => backend.lastPushed(device.id) != null);

        final pushed = backend.lastPushed(device.id)!;
        expect(pushed['name'], 'Web Test Cihazı');
        expect(pushed['category'], 'Diğer');
        expect((pushed['tasks'] as List).single['id'], task.id, reason: 'web sayfası göreve bu numarayla kayıt bırakır');

        await webService.deleteDevice(device.id);
        await eventually(() => backend.deletedDevices.contains(device.id));
      });

      test('web\'de düzenlenen notu cihaza işler, onaylar ve ara depoya geri gönderir', () async {
        final oralB = await deviceNamed('Oral-B Şarjlı Diş Fırçası');
        final editedAt = DateTime.now().toUtc().toIso8601String();
        backend.pendingNotes.addAll([
          {'noteId': 'n1', 'deviceId': oralB.id, 'text': 'Başlık: EB-18', 'editedAt': editedAt},
          {'noteId': 'n2', 'deviceId': 999999, 'text': 'silinmiş cihaz', 'editedAt': editedAt},
        ]);

        final result = (await webService.syncWithBackend())!;

        expect(result.notesUpdated, 1, reason: 'cihazı olmayan not sayılmaz');
        expect((await deviceNamed('Oral-B Şarjlı Diş Fırçası')).notes, 'Başlık: EB-18');
        expect(backend.acknowledgedNotes, unorderedEquals(['n1', 'n2']), reason: 'karşılığı olmayan not da onaylanır');
        expect(backend.lastPushed(oralB.id)!['notes'], 'Başlık: EB-18', reason: 'web sayfası yeni notu görmeli');
      });

      test('aynı not yeniden gelirse sayılmaz; web\'de silinen not cihazdan da silinir', () async {
        final philips = await deviceNamed('Philips Kahve Makinesi');
        philips.notes = 'Eski not';
        await isar.writeTxn(() => isar.deviceModels.put(philips));
        final editedAt = DateTime.now().toUtc().toIso8601String();

        backend.pendingNotes.add({'noteId': 'n3', 'deviceId': philips.id, 'text': 'Eski not', 'editedAt': editedAt});
        expect((await webService.syncWithBackend())!.notesUpdated, 0, reason: 'metin zaten aynı');

        backend.pendingNotes.add({'noteId': 'n4', 'deviceId': philips.id, 'text': '', 'editedAt': editedAt});
        expect((await webService.syncWithBackend())!.notesUpdated, 1);
        expect((await deviceNamed('Philips Kahve Makinesi')).notes, '');
        expect(backend.lastPushed(philips.id)!.containsKey('notes'), isFalse);
      });

      test('fotoğraflı cihazın küçük resmi bir kez yüklenir; fotoğraf kalkınca ara depodan da silinir', () async {
        final oralB = await deviceNamed('Oral-B Şarjlı Diş Fırçası');
        final photo = File('${tempDir.path}${Platform.pathSeparator}oralb.png')
          ..writeAsBytesSync(img.encodePng(img.Image(width: 400, height: 300)));
        oralB.imagePath = photo.path;
        await isar.writeTxn(() => isar.deviceModels.put(oralB));
        int uploads() => backend.requests.where((r) => r['action'] == 'putImage').length;

        await webService.syncWithBackend();

        expect(backend.images[oralB.id]!.data, startsWith('data:image/jpeg;base64,'));
        expect(uploads(), 1);

        await webService.syncWithBackend();
        expect(uploads(), 1, reason: 'dosya değişmedi, resim yeniden gönderilmez');

        oralB.imagePath = null;
        await isar.writeTxn(() => isar.deviceModels.put(oralB));
        await webService.syncWithBackend();
        expect(backend.images.containsKey(oralB.id), isFalse, reason: 'fotoğraf kaldırıldı');
      });

      test('resim yüklenemese de eşitleme başarılı sayılır', () async {
        final philips = await deviceNamed('Philips Kahve Makinesi');
        final photo = File('${tempDir.path}${Platform.pathSeparator}bozuk.jpg')..writeAsBytesSync([1, 2, 3]);
        philips.imagePath = photo.path;
        await isar.writeTxn(() => isar.deviceModels.put(philips));

        final result = (await webService.syncWithBackend())!;

        expect(result.pushError, isNull);
        expect(backend.images.containsKey(philips.id), isFalse, reason: 'çözülemeyen dosya yüklenmez');

        philips.imagePath = null;
        await isar.writeTxn(() => isar.deviceModels.put(philips));
      });

      test('uygulama içi bakım kaydı güncel tarihi ara depoya gönderir', () async {
        final xiaomi = await deviceNamed('Xiaomi Mop Pro Robot Süpürge');
        final task = xiaomi.tasks.first;
        final startedAt = DateTime.now();

        await webService.recordSelectedTasks(xiaomi.id, {task.id});
        await eventually(() => backend.lastPushed(xiaomi.id) != null);

        final pushedTask = (backend.lastPushed(xiaomi.id)!['tasks'] as List)
            .cast<Map<String, dynamic>>()
            .firstWhere((t) => t['id'] == task.id);
        expect(DateTime.parse(pushedTask['lastCompletedAt'] as String).isBefore(startedAt), isFalse);
      });
    });

    test('cihaz sayfasındaki not kutusu yalnızca notu günceller; model ve fiyat kalıcıdır', () async {
      final daikin = await deviceNamed('Daikin Klima');
      final taskIds = daikin.tasks.map((t) => t.id).toSet();
      daikin
        ..modelInfo = 'Daikin FTXM35'
        ..price = 24990.5;
      await isar.writeTxn(() => isar.deviceModels.put(daikin));

      await service.updateDeviceNotes(daikin.id, 'Filtre ayda bir yıkanır');

      final reloaded = await deviceNamed('Daikin Klima');
      expect(reloaded.notes, 'Filtre ayda bir yıkanır');
      expect(reloaded.modelInfo, 'Daikin FTXM35');
      expect(reloaded.price, 24990.5);
      expect(reloaded.tasks.map((t) => t.id).toSet(), taskIds);
    });
  });
}
