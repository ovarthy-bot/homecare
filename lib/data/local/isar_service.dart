import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import '../models/device_model.dart';
import '../models/task_model.dart';
import '../models/history_model.dart';
import '../models/settings_model.dart';
import '../models/maintenance_receipt.dart';
import '../models/device_categories.dart';
import 'dart:convert';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import '../../core/services/notification_service.dart';
import '../../core/services/github_service.dart';
import '../../core/services/backend_service.dart';

class IsarService {
  late Future<Isar> db;
  final GithubService _githubService = GithubService();
  final BackendService _backend;

  IsarService({BackendService? backend}) : _backend = backend ?? BackendService() {
    db = openDB();
  }

  Future<Isar> openDB() async {
    if (Isar.instanceNames.isEmpty) {
      final dir = await getApplicationDocumentsDirectory();
      final isar = await Isar.open(
        [DeviceModelSchema, TaskModelSchema, HistoryModelSchema, SettingsModelSchema],
        directory: dir.path,
        inspector: true,
      );
      
      // Perform seeding if DB is empty
      if (await isar.deviceModels.count() == 0) {
        await _seedInitialData(isar);
      }
      
      if (await isar.settingsModels.count() == 0) {
        await isar.writeTxn(() async {
          await isar.settingsModels.put(SettingsModel());
        });
      }
      
      return isar;
    }

    return Future.value(Isar.getInstance());
  }

  Future<void> _seedInitialData(Isar isar) async {
    await isar.writeTxn(() async {
      // 1. Epson Yazıcı
      final epson = DeviceModel()
        ..name = 'Epson Yazıcı'
        ..room = 'Çalışma Odası'
        ..category = DeviceCategories.electronics.label;
      
      final epsonTasks = [
        TaskModel()..name = 'Yazıcı kartuş temizleme'..intervalDays = 30..lastCompletedAt = DateTime.now(),
        TaskModel()..name = 'Kartuş kafası hizalama'..intervalDays = 90..lastCompletedAt = DateTime.now(),
      ];

      // 2. Philips Kahve Makinesi
      final philips = DeviceModel()
        ..name = 'Philips Kahve Makinesi'
        ..room = 'Mutfak'
        ..category = DeviceCategories.kitchen.label;
      
      final philipsTasks = [
        TaskModel()..name = 'Çöp haznesi temizliği'..intervalDays = 7..lastCompletedAt = DateTime.now(),
        TaskModel()..name = 'Demlik temizliği'..intervalDays = 7..lastCompletedAt = DateTime.now(),
        TaskModel()..name = 'Kireç çözme'..intervalDays = 60..lastCompletedAt = DateTime.now(),
      ];

      // 3. Xiaomi Mop Pro
      final xiaomi = DeviceModel()
        ..name = 'Xiaomi Mop Pro Robot Süpürge'
        ..room = 'Salon'
        ..category = DeviceCategories.cleaning.label;
      
      final xiaomiTasks = [
        TaskModel()..name = 'Ana fırça temizliği'..intervalDays = 14..lastCompletedAt = DateTime.now(),
        TaskModel()..name = 'Çöp haznesi temizliği'..intervalDays = 3..lastCompletedAt = DateTime.now(),
      ];

      // 4. Daikin Klima
      final daikin = DeviceModel()
        ..name = 'Daikin Klima'
        ..room = 'Salon'
        ..category = DeviceCategories.climate.label;
      
      final daikinTasks = [
        TaskModel()..name = 'Filtre temizliği'..intervalDays = 30..lastCompletedAt = DateTime.now(),
      ];

      // 5. Oral-B
      final oralB = DeviceModel()
        ..name = 'Oral-B Şarjlı Diş Fırçası'
        ..room = 'Banyo'
        ..category = DeviceCategories.personalCare.label;
      
      final oralBTasks = [
        TaskModel()..name = 'Fırça başlığı değişimi'..intervalDays = 90..lastCompletedAt = DateTime.now(),
      ];

      final devices = [epson, philips, xiaomi, daikin, oralB];
      final allTasks = [epsonTasks, philipsTasks, xiaomiTasks, daikinTasks, oralBTasks];

      for (int i = 0; i < devices.length; i++) {
        final device = devices[i];
        final tasks = allTasks[i];
        
        await isar.deviceModels.put(device);
        
        for (var task in tasks) {
          task.device.value = device;
          await isar.taskModels.put(task);
          device.tasks.add(task);
        }
        await device.tasks.save();
      }
    });
  }

  /// Cihaz ya da görev değiştiğinde (ör. karekodla bakım kaydı) görevleri yüklü cihaz listesini yeniden yayar.
  Stream<List<DeviceModel>> listenToDevices() {
    late final StreamController<List<DeviceModel>> controller;
    final subscriptions = <StreamSubscription<void>>[];
    // Üst üste gelen değişiklikler sırayla işlenir; eski sonuç yenisinin önüne geçmez.
    var pending = Future<void>.value();

    Future<void> emitDevices(Isar isar) async {
      final devices = await isar.deviceModels.where().findAll();
      for (final device in devices) {
        await device.tasks.load();
      }
      if (controller.hasListener) controller.add(devices);
    }

    controller = StreamController<List<DeviceModel>>(
      onListen: () async {
        final isar = await db;
        if (!controller.hasListener) return;

        void onChange(void _) {
          pending = pending.then((_) => emitDevices(isar)).catchError((Object e, StackTrace st) {
            if (controller.hasListener) controller.addError(e, st);
          });
        }

        subscriptions.add(isar.deviceModels.watchLazy(fireImmediately: true).listen(onChange));
        subscriptions.add(isar.taskModels.watchLazy().listen(onChange));
      },
      onCancel: () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      },
    );
    return controller.stream;
  }

  Future<List<DeviceModel>> getDevices() async {
    final isar = await db;
    return await isar.deviceModels.where().findAll();
  }

  Future<void> saveDeviceWithTasks(DeviceModel device, List<TaskModel> tasks) async {
    final isar = await db;
    await isar.writeTxn(() async {
      await isar.deviceModels.put(device);
      
      await device.tasks.load();
      
      // Mevcut ama yeni listede olmayan görevleri sil
      final newTaskIds = tasks.map((t) => t.id).toSet();
      final tasksToDelete = device.tasks.where((t) => !newTaskIds.contains(t.id)).toList();
      
      for (var oldTask in tasksToDelete) {
        device.tasks.remove(oldTask);
        await isar.taskModels.delete(oldTask.id);
      }

      // Yeni veya güncellenen görevleri kaydet
      final settings = await isar.settingsModels.where().findFirst() ?? SettingsModel();

      for (var task in tasks) {
        task.device.value = device;
        await isar.taskModels.put(task);
        device.tasks.add(task);

        // Bildirim ayarla
        await _scheduleReminder(device, task, settings);
      }
      
      await device.tasks.save();
      
      // Sync to GitHub
      _githubService.syncDeviceToGithub(device, settings);
    });

    unawaited(_pushDevice(device.id));
  }

  /// Cihaz sayfasındaki not kutusu için: yalnızca notu günceller; görevlere ve hatırlatmalara dokunmaz.
  Future<void> updateDeviceNotes(int deviceId, String notes) async {
    final isar = await db;
    final device = await isar.writeTxn(() async {
      final device = await isar.deviceModels.get(deviceId);
      if (device == null) return null;
      device.notes = notes;
      await isar.deviceModels.put(device);
      return device;
    });
    if (device == null) return;

    // Not web sayfasında da göründüğü için diğer cihaz değişiklikleri gibi dışarıya yansır.
    await device.tasks.load();
    final settings = await getSettings();
    unawaited(_githubService.syncDeviceToGithub(device, settings));
    unawaited(_pushDevice(deviceId));
  }

  Future<void> _scheduleReminder(DeviceModel device, TaskModel task, SettingsModel settings) async {
    if (!settings.notificationsEnabled || !task.nextDueDate.isAfter(DateTime.now())) return;

    final reminderDate = task.nextDueDate.subtract(Duration(days: settings.defaultReminderDays));
    if (!reminderDate.isAfter(DateTime.now())) return;

    await NotificationService().scheduleMaintenanceReminder(
      task.id,
      'Bakım Hatırlatması',
      '${device.name} için ${task.name} vakti yaklaştı.',
      reminderDate,
    );
  }

  /// Görevlerin hatırlatmasını güncel tarihe göre yeniden kurar (eskisini iptal eder).
  Future<void> _refreshReminders(DeviceModel device, Iterable<TaskModel> tasks) async {
    final settings = await getSettings();
    for (final task in tasks) {
      try {
        await NotificationService().cancelNotification(task.id);
      } catch (e) {
        // Bildirim eklentisi olmayan platformlarda sessizce geç.
      }
      await _scheduleReminder(device, task, settings);
    }
  }

  Future<DeviceModel?> getDeviceById(int id) async {
    final isar = await db;
    final device = await isar.deviceModels.get(id);
    if (device != null) {
      await device.tasks.load();
    }
    return device;
  }

  Future<void> deleteDevice(int id) async {
    final isar = await db;
    await isar.writeTxn(() async {
      final device = await isar.deviceModels.get(id);
      if (device != null) {
        await device.tasks.load();
        for (var task in device.tasks) {
          await isar.taskModels.delete(task.id);
        }
        await isar.deviceModels.delete(id);
        
        final settings = await isar.settingsModels.where().findFirst() ?? SettingsModel();
        _githubService.deleteDeviceFromGithub(id, settings);
      }
    });

    unawaited(_deleteRemote(id));
  }

  Future<void> logTaskCompletion(int deviceId, String deviceName, String taskName) async {
    final isar = await db;
    await isar.writeTxn(() async {
      final history = HistoryModel()
        ..deviceId = deviceId
        ..deviceName = deviceName
        ..taskName = taskName
        ..completedAt = DateTime.now();
      await isar.historyModels.put(history);
    });
  }

  /// Karekod okutulduğunda çağrılır. Cihazın tek bakım görevi varsa onu soru sormadan kaydeder.
  ///
  /// Birden fazla görev varsa hiçbir şey kaydetmeden [MaintenanceOutcome.needsSelection]
  /// döner; hangi görevin yapıldığını kullanıcı seçer ([recordSelectedTasks]).
  /// Tek görevli cihazda [duplicateWindow] içinde kayıt varsa (aynı bağlantının ikinci
  /// kez gelmesi gibi) yeni kayıt açılmaz. Cihaz bulunamazsa `null` döner.
  Future<MaintenanceReceipt?> recordMaintenanceViaQr(
    int deviceId, {
    Duration duplicateWindow = const Duration(seconds: 60),
  }) async {
    final isar = await db;
    final device = await getDeviceById(deviceId);
    if (device == null) return null;

    if (device.tasks.length > 1) {
      return MaintenanceReceipt(
        deviceId: device.id,
        deviceName: device.name,
        outcome: MaintenanceOutcome.needsSelection,
      );
    }

    final recent = await isar.historyModels
        .filter()
        .deviceIdEqualTo(deviceId)
        .completedAtGreaterThan(DateTime.now().subtract(duplicateWindow))
        .findAll();
    if (recent.isNotEmpty) {
      return MaintenanceReceipt(
        deviceId: device.id,
        deviceName: device.name,
        outcome: MaintenanceOutcome.alreadyRecorded,
        alreadyRecordedTaskNames: recent.map((h) => h.taskName).toList(),
      );
    }

    return _recordTasks(isar, device, device.tasks.toList());
  }

  /// Kullanıcının seçtiği görevleri kaydeder. Cihaz bulunamazsa `null` döner.
  Future<MaintenanceReceipt?> recordSelectedTasks(int deviceId, Set<int> taskIds) async {
    final isar = await db;
    final device = await getDeviceById(deviceId);
    if (device == null) return null;

    return _recordTasks(isar, device, device.tasks.where((t) => taskIds.contains(t.id)).toList());
  }

  Future<MaintenanceReceipt> _recordTasks(Isar isar, DeviceModel device, List<TaskModel> selected) async {
    if (selected.isEmpty) {
      return MaintenanceReceipt(
        deviceId: device.id,
        deviceName: device.name,
        outcome: MaintenanceOutcome.noTasks,
      );
    }

    final now = DateTime.now();
    final recorded = <RecordedTask>[];
    await isar.writeTxn(() async {
      for (final task in selected) {
        final previous = task.lastCompletedAt;
        final historyId = await isar.historyModels.put(
          HistoryModel()
            ..deviceId = device.id
            ..deviceName = device.name
            ..taskName = task.name
            ..completedAt = now,
        );
        task.lastCompletedAt = now;
        await isar.taskModels.put(task);
        recorded.add(RecordedTask(
          taskId: task.id,
          taskName: task.name,
          historyId: historyId,
          previousCompletedAt: previous,
          nextDueDate: task.nextDueDate,
        ));
      }
    });

    await _refreshReminders(device, selected);
    unawaited(_pushDevice(device.id));

    return MaintenanceReceipt(
      deviceId: device.id,
      deviceName: device.name,
      outcome: MaintenanceOutcome.recorded,
      recorded: recorded,
    );
  }

  /// Karekodla açılan kayıtları ([recordMaintenanceViaQr], [recordSelectedTasks]) siler ve
  /// görevleri eski tarihine döndürür.
  Future<void> undoMaintenance(MaintenanceReceipt receipt) async {
    if (!receipt.canUndo) return;

    final isar = await db;
    final restored = <TaskModel>[];
    await isar.writeTxn(() async {
      for (final entry in receipt.recorded) {
        await isar.historyModels.delete(entry.historyId);
        final task = await isar.taskModels.get(entry.taskId);
        if (task == null) continue;
        task.lastCompletedAt = entry.previousCompletedAt;
        await isar.taskModels.put(task);
        restored.add(task);
      }
    });

    final device = await isar.deviceModels.get(receipt.deviceId);
    if (device != null) await _refreshReminders(device, restored);
    unawaited(_pushDevice(receipt.deviceId));
  }

  // --- Ara depo (web'den bakım kaydı) -------------------------------------------------------

  /// Cihazı ara depoya gönderir. En iyi çaba: kurulu değilse ya da ağ yoksa sessizce geçer.
  Future<void> _pushDevice(int deviceId) async {
    try {
      final settings = await getSettings();
      if (!BackendService.isConfigured(settings)) return;
      final device = await getDeviceById(deviceId);
      if (device == null) return;
      await _backend.pushDevices(settings, [device]);
    } catch (e) {
      debugPrint('Cihaz ara depoya gönderilemedi: $e');
    }
  }

  Future<void> _deleteRemote(int deviceId) async {
    try {
      final settings = await getSettings();
      if (!BackendService.isConfigured(settings)) return;
      await _backend.deleteDevice(settings, deviceId);
    } catch (e) {
      debugPrint('Cihaz ara depodan silinemedi: $e');
    }
  }

  /// Ara depodaki bekleyen web kayıtlarını ve web'de düzenlenen notları telefona alır, sonra tüm
  /// cihazları (güncel bakım tarihleri ve notlarla) ara depoya gönderir. Kurulu değilse `null`
  /// döner; kayıtlar alınamazsa [BackendException] fırlatır. Cihazların gönderilememesi sonucu
  /// bozmaz, `pushError`a yazılır.
  Future<WebSyncResult?> syncWithBackend() async {
    final settings = await getSettings();
    if (!BackendService.isConfigured(settings)) return null;

    final inbox = await _backend.pull(settings);
    final imported = await _importWebRecords(inbox.records);
    final notesUpdated = await _importWebNotes(inbox.notes);
    // Alınan ve bu telefonda karşılığı olmayan her kayıt onaylanır; yoksa her eşitlemede yeniden gelir.
    await _backend.acknowledge(
      settings,
      inbox.records.map((r) => r.recordId).toList(),
      noteIds: inbox.notes.map((n) => n.noteId).toList(),
    );

    var pushedDevices = 0;
    String? pushError;
    try {
      final devices = await getDevices();
      for (final device in devices) {
        await device.tasks.load();
      }
      await _backend.pushDevices(settings, devices);
      pushedDevices = devices.length;
    } catch (e) {
      pushError = '$e';
    }

    return WebSyncResult(
      imported: imported.imported,
      notesUpdated: notesUpdated,
      unmatched: imported.unmatched,
      pushedDevices: pushedDevices,
      pushError: pushError,
    );
  }

  /// Web'de yazılan notları cihazlara işler; notu değişen cihaz sayısını döner. Aynı metin yeniden
  /// gelirse (onay gidememişse) bir şey değişmez.
  Future<int> _importWebNotes(List<WebNote> notes) async {
    if (notes.isEmpty) return 0;

    final isar = await db;
    var updated = 0;
    await isar.writeTxn(() async {
      final oldestFirst = [...notes]..sort((a, b) => a.editedAt.compareTo(b.editedAt));
      for (final note in oldestFirst) {
        final device = await isar.deviceModels.get(note.deviceId);
        if (device == null || (device.notes ?? '') == note.text) continue;
        device.notes = note.text;
        await isar.deviceModels.put(device);
        updated++;
      }
    });
    return updated;
  }

  Future<({int imported, int unmatched})> _importWebRecords(List<WebRecord> records) async {
    if (records.isEmpty) return (imported: 0, unmatched: 0);

    final isar = await db;
    var imported = 0;
    var unmatched = 0;
    final devices = <int, DeviceModel?>{};
    final touched = <int, List<TaskModel>>{};

    await isar.writeTxn(() async {
      for (final record in records) {
        // Daha önce alınmış ama onayı gidememiş kayıt: tekrar ekleme.
        final alreadyImported = await isar.historyModels.filter().externalIdEqualTo(record.recordId).findFirst();
        if (alreadyImported != null) continue;

        if (!devices.containsKey(record.deviceId)) {
          final device = await isar.deviceModels.get(record.deviceId);
          await device?.tasks.load();
          devices[record.deviceId] = device;
        }
        final device = devices[record.deviceId];
        final task = device?.tasks.where((t) => t.id == record.taskId).firstOrNull;
        if (device == null || task == null) {
          unmatched++;
          continue;
        }

        await isar.historyModels.put(
          HistoryModel()
            ..deviceId = device.id
            ..deviceName = device.name
            ..taskName = task.name
            ..completedAt = record.recordedAt
            ..source = HistoryModel.sourceWeb
            ..externalId = record.recordId,
        );

        final last = task.lastCompletedAt;
        if (last == null || record.recordedAt.isAfter(last)) {
          task.lastCompletedAt = record.recordedAt;
          await isar.taskModels.put(task);
        }
        touched.putIfAbsent(device.id, () => []).add(task);
        imported++;
      }
    });

    for (final entry in touched.entries) {
      await _refreshReminders(devices[entry.key]!, entry.value);
    }
    return (imported: imported, unmatched: unmatched);
  }

  Stream<List<HistoryModel>> listenToHistory() async* {
    final isar = await db;
    yield* isar.historyModels.where().sortByCompletedAtDesc().watch(fireImmediately: true);
  }

  Future<SettingsModel> getSettings() async {
    final isar = await db;
    final settings = await isar.settingsModels.where().findFirst();
    return settings ?? SettingsModel();
  }

  Future<void> updateSettings(SettingsModel settings) async {
    final isar = await db;
    await isar.writeTxn(() async {
      await isar.settingsModels.put(settings);
    });
  }

  Future<void> exportDataAsJson() async {
    final isar = await db;
    final devices = await isar.deviceModels.where().findAll();
    
    List<Map<String, dynamic>> deviceList = [];
    for (var d in devices) {
      await d.tasks.load();
      deviceList.add({
        'id': d.id,
        'name': d.name,
        'room': d.room,
        'category': d.category,
        'modelInfo': d.modelInfo,
        'price': d.price,
        'notes': d.notes,
        'serviceInfo': d.serviceInfo,
        'purchaseDate': d.purchaseDate?.toIso8601String(),
        'imagePath': d.imagePath,
        'tasks': d.tasks.map((t) => {
          'name': t.name,
          'intervalDays': t.intervalDays,
          'lastCompletedAt': t.lastCompletedAt?.toIso8601String()
        }).toList(),
      });
    }

    final jsonStr = jsonEncode({'devices': deviceList});
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/homecare_export.json');
    await file.writeAsString(jsonStr);
    
    // ignore: deprecated_member_use
    await Share.shareXFiles([XFile(file.path)], text: 'Ev Sağlığı Cihaz Verileri');
  }

  Future<void> importDataFromJson(String jsonString, {bool clearExisting = false}) async {
    final data = jsonDecode(jsonString);
    if (data['devices'] == null) throw Exception('Geçersiz veri formatı');
    
    final isar = await db;
    await isar.writeTxn(() async {
      if (clearExisting) {
        await isar.deviceModels.clear();
        await isar.taskModels.clear();
      }
      
      final devicesList = data['devices'] as List;
      for (var d in devicesList) {
        final device = DeviceModel()
          ..name = d['name'] ?? 'İsimsiz Cihaz'
          ..room = d['room'] ?? ''
          ..category = d['category']
          ..modelInfo = d['modelInfo']
          ..price = (d['price'] as num?)?.toDouble()
          ..notes = d['notes']
          ..serviceInfo = d['serviceInfo']
          ..imagePath = d['imagePath'];
          
        if (d['purchaseDate'] != null) {
          device.purchaseDate = DateTime.tryParse(d['purchaseDate']);
        }
        
        await isar.deviceModels.put(device);
        
        final tasksList = d['tasks'] as List?;
        if (tasksList != null) {
          for (var t in tasksList) {
            final task = TaskModel()
              ..name = t['name'] ?? 'İsimsiz Görev'
              ..intervalDays = t['intervalDays'] ?? 30;
              
            if (t['lastCompletedAt'] != null) {
              task.lastCompletedAt = DateTime.tryParse(t['lastCompletedAt']);
            }
            
            task.device.value = device;
            await isar.taskModels.put(task);
            device.tasks.add(task);
          }
          await device.tasks.save();
        }
      }
    });
  }
}
