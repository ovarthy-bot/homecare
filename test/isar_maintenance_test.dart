// Gerçek Isar ile karekod bakım kaydını sınar. Yalnızca Windows'ta ve paketle gelen
// isar.dll bulunabiliyorsa çalışır; veritabanı geçici bir klasörde açılır.
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:homecare/data/local/isar_service.dart';
import 'package:homecare/data/models/device_model.dart';
import 'package:homecare/data/models/history_model.dart';
import 'package:homecare/data/models/maintenance_receipt.dart';
import 'package:homecare/data/models/task_model.dart';

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
  });
}
