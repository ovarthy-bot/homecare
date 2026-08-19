import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import '../models/device_model.dart';
import '../models/task_model.dart';
import '../models/history_model.dart';
import '../models/settings_model.dart';
import 'dart:convert';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import '../../core/services/notification_service.dart';

class IsarService {
  late Future<Isar> db;

  IsarService() {
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
        ..room = 'Çalışma Odası';
      
      final epsonTasks = [
        TaskModel()..name = 'Yazıcı kartuş temizleme'..intervalDays = 30..lastCompletedAt = DateTime.now(),
        TaskModel()..name = 'Kartuş kafası hizalama'..intervalDays = 90..lastCompletedAt = DateTime.now(),
      ];

      // 2. Philips Kahve Makinesi
      final philips = DeviceModel()
        ..name = 'Philips Kahve Makinesi'
        ..room = 'Mutfak';
      
      final philipsTasks = [
        TaskModel()..name = 'Çöp haznesi temizliği'..intervalDays = 7..lastCompletedAt = DateTime.now(),
        TaskModel()..name = 'Demlik temizliği'..intervalDays = 7..lastCompletedAt = DateTime.now(),
        TaskModel()..name = 'Kireç çözme'..intervalDays = 60..lastCompletedAt = DateTime.now(),
      ];

      // 3. Xiaomi Mop Pro
      final xiaomi = DeviceModel()
        ..name = 'Xiaomi Mop Pro Robot Süpürge'
        ..room = 'Salon';
      
      final xiaomiTasks = [
        TaskModel()..name = 'Ana fırça temizliği'..intervalDays = 14..lastCompletedAt = DateTime.now(),
        TaskModel()..name = 'Çöp haznesi temizliği'..intervalDays = 3..lastCompletedAt = DateTime.now(),
      ];

      // 4. Daikin Klima
      final daikin = DeviceModel()
        ..name = 'Daikin Klima'
        ..room = 'Salon';
      
      final daikinTasks = [
        TaskModel()..name = 'Filtre temizliği'..intervalDays = 30..lastCompletedAt = DateTime.now(),
      ];

      // 5. Oral-B
      final oralB = DeviceModel()
        ..name = 'Oral-B Şarjlı Diş Fırçası'
        ..room = 'Banyo';
      
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

  Stream<List<DeviceModel>> listenToDevices() async* {
    final isar = await db;
    await for (final devices in isar.deviceModels.where().watch(fireImmediately: true)) {
      for (final device in devices) {
        await device.tasks.load();
      }
      yield devices;
    }
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
        if (settings.notificationsEnabled && task.nextDueDate.isAfter(DateTime.now())) {
          final reminderDate = task.nextDueDate.subtract(Duration(days: settings.defaultReminderDays));
          if (reminderDate.isAfter(DateTime.now())) {
            await NotificationService().scheduleMaintenanceReminder(
              task.id,
              'Bakım Hatırlatması',
              '${device.name} için ${task.name} vakti yaklaştı.',
              reminderDate,
            );
          }
        }
      }
      
      await device.tasks.save();
    });
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
      }
    });
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
