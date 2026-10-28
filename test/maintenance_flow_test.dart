import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:isar/isar.dart';

import 'package:homecare/core/deep_link/deep_link.dart';
import 'package:homecare/core/routing/app_router.dart';
import 'package:homecare/data/local/isar_service.dart';
import 'package:homecare/data/models/device_model.dart';
import 'package:homecare/data/models/maintenance_receipt.dart';
import 'package:homecare/data/models/task_model.dart';
import 'package:homecare/features/dashboard/presentation/providers/dashboard_providers.dart';

/// Isar'ı açmadan yalnızca bakım kaydı çağrılarını kaydeden sahte servis.
class FakeIsarService implements IsarService {
  final MaintenanceReceipt? receipt;
  final DeviceModel? device;
  final MaintenanceReceipt? selectionReceipt;
  final recordedDeviceIds = <int>[];
  final selections = <Set<int>>[];
  final undone = <MaintenanceReceipt>[];

  FakeIsarService(this.receipt, {this.device, this.selectionReceipt});

  @override
  Future<MaintenanceReceipt?> recordMaintenanceViaQr(
    int deviceId, {
    Duration duplicateWindow = const Duration(seconds: 60),
  }) async {
    recordedDeviceIds.add(deviceId);
    return receipt;
  }

  @override
  Future<DeviceModel?> getDeviceById(int id) async => device;

  @override
  Future<MaintenanceReceipt?> recordSelectedTasks(int deviceId, Set<int> taskIds) async {
    selections.add(taskIds);
    return selectionReceipt;
  }

  @override
  Future<void> undoMaintenance(MaintenanceReceipt receipt) async => undone.add(receipt);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MaintenanceReceipt coffeeMachineReceipt(MaintenanceOutcome outcome) {
  return MaintenanceReceipt(
    deviceId: 3,
    deviceName: 'Philips Kahve Makinesi',
    outcome: outcome,
    recorded: outcome == MaintenanceOutcome.recorded
        ? [
            RecordedTask(
              taskId: 11,
              taskName: 'Kireç çözme',
              historyId: 21,
              previousCompletedAt: DateTime(2026, 9, 1),
              nextDueDate: DateTime(2026, 12, 27),
            ),
          ]
        : const [],
    alreadyRecordedTaskNames: outcome == MaintenanceOutcome.alreadyRecorded ? ['Kireç çözme'] : const [],
  );
}

TaskModel taskOf(int id, String name, {required int intervalDays, required int completedDaysAgo}) {
  return TaskModel()
    ..id = id
    ..name = name
    ..intervalDays = intervalDays
    ..lastCompletedAt = DateTime.now().subtract(Duration(days: completedDaysAgo));
}

// ignore: subtype_of_sealed_class
/// Veritabanına bağlı olmayan `IsarLinks` öğeleri yineleyemez; testte görevleri bellekten verir.
class _FakeLinks extends SetBase<TaskModel> implements IsarLinks<TaskModel> {
  final Set<TaskModel> _items;

  _FakeLinks(Iterable<TaskModel> items) : _items = items.toSet();

  @override
  bool add(TaskModel value) => _items.add(value);

  @override
  bool contains(Object? element) => _items.contains(element);

  @override
  Iterator<TaskModel> get iterator => _items.iterator;

  @override
  int get length => _items.length;

  @override
  TaskModel? lookup(Object? element) => _items.lookup(element);

  @override
  bool remove(Object? value) => _items.remove(value);

  @override
  Set<TaskModel> toSet() => _items.toSet();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestDevice extends DeviceModel {
  final IsarLinks<TaskModel> _links;

  _TestDevice(List<TaskModel> tasks) : _links = _FakeLinks(tasks);

  @override
  IsarLinks<TaskModel> get tasks => _links;
}

/// Üç görevli kahve makinesi: yalnızca "Çöp haznesi" gecikmiş, diğerlerinin zamanı gelmemiş.
DeviceModel coffeeMachine() {
  return _TestDevice([
    taskOf(11, 'Kireç çözme', intervalDays: 60, completedDaysAgo: 5),
    taskOf(12, 'Çöp haznesi temizliği', intervalDays: 7, completedDaysAgo: 10),
    taskOf(13, 'Demlik temizliği', intervalDays: 7, completedDaysAgo: 1),
  ])
    ..id = 3
    ..name = 'Philips Kahve Makinesi'
    ..room = 'Mutfak';
}

FakeIsarService multiTaskService({MaintenanceReceipt? selectionReceipt}) {
  return FakeIsarService(
    coffeeMachineReceipt(MaintenanceOutcome.needsSelection),
    device: coffeeMachine(),
    selectionReceipt: selectionReceipt,
  );
}

bool isChecked(WidgetTester tester, String taskName) {
  return tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, taskName)).value!;
}

/// Gerçek yönlendiriciyi ve ekranları kurar; yalnızca veri katmanı sahtedir.
Future<GoRouter> pumpApp(WidgetTester tester, FakeIsarService service) async {
  final container = ProviderContainer(
    overrides: [
      isarServiceProvider.overrideWithValue(service),
      devicesProvider.overrideWith((ref) => Stream.value(<DeviceModel>[])),
    ],
  );
  addTearDown(container.dispose);

  final router = container.read(appRouterProvider);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  const dashboardTitle = 'Ev Sağlığı';
  const successTitle = 'Philips Kahve Makinesi Bakımı Kaydedildi!';

  testWidgets('karekod bağlantısı bakımı soru sormadan kaydeder, başarıyı gösterir ve ana sayfaya döner',
      (tester) async {
    final service = FakeIsarService(coffeeMachineReceipt(MaintenanceOutcome.recorded));
    final router = await pumpApp(tester, service);
    expect(find.text(dashboardTitle), findsOneWidget);

    router.go(DeepLink.maintenanceDoneLink(3));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(service.recordedDeviceIds, [3]);
    expect(find.text(successTitle), findsOneWidget);
    expect(find.textContaining('Kireç çözme'), findsOneWidget);
    expect(find.textContaining('Sonraki: 27 Ara 2026'), findsOneWidget);

    // Hiçbir tuşa basılmadan süre dolunca kapanır.
    await tester.pumpAndSettle(const Duration(seconds: 5));
    expect(find.text(successTitle), findsNothing);
    expect(find.text(dashboardTitle), findsOneWidget);
    expect(service.undone, isEmpty);
    expect(service.recordedDeviceIds, [3], reason: 'bağlantı tek kayıt açmalı');
  });

  testWidgets('"Geri Al" kaydı geri alır ve otomatik kapanmayı durdurup kendisi kapanır', (tester) async {
    final receipt = coffeeMachineReceipt(MaintenanceOutcome.recorded);
    final service = FakeIsarService(receipt);
    final router = await pumpApp(tester, service);

    router.go(DeepLink.maintenanceDoneLink(3));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Geri Al'));
    await tester.pump();

    expect(service.undone, [receipt]);
    expect(find.text('Kayıt geri alındı'), findsOneWidget);

    await tester.pumpAndSettle(const Duration(seconds: 5));
    expect(find.text(dashboardTitle), findsOneWidget);
  });

  testWidgets('aynı bakım az önce kaydedildiyse bunu söyler ve geri alma sunmaz', (tester) async {
    final service = FakeIsarService(coffeeMachineReceipt(MaintenanceOutcome.alreadyRecorded));
    final router = await pumpApp(tester, service);

    router.go(DeepLink.maintenanceDoneLink(3));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Bu bakım az önce kaydedilmişti'), findsOneWidget);
    expect(find.text('Geri Al'), findsNothing);

    await tester.pumpAndSettle(const Duration(seconds: 5));
    expect(find.text(dashboardTitle), findsOneWidget);
  });

  testWidgets('bu telefonda olmayan cihaz için açıklama gösterir ve kendiliğinden kapanmaz', (tester) async {
    final service = FakeIsarService(null);
    final router = await pumpApp(tester, service);

    router.go(DeepLink.maintenanceDoneLink(99));
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));

    expect(service.recordedDeviceIds, [99]);
    expect(find.text('Cihaz bulunamadı'), findsOneWidget);

    await tester.tap(find.text('Ana Sayfa'));
    await tester.pumpAndSettle();
    expect(find.text(dashboardTitle), findsOneWidget);
  });

  testWidgets('bakım görevi olmayan cihazda kayıt açmaz, görev eklemeye yönlendirir', (tester) async {
    final service = FakeIsarService(coffeeMachineReceipt(MaintenanceOutcome.noTasks));
    final router = await pumpApp(tester, service);

    router.go(DeepLink.maintenanceDoneLink(3));
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));

    expect(find.text('Philips Kahve Makinesi için bakım görevi yok'), findsOneWidget);
    expect(find.text('Cihaza Git'), findsOneWidget);
  });

  group('birden fazla bakım görevi olan cihaz', () {
    testWidgets('kayıt açmadan görevleri listeler; zamanı gelmiş olan önceden işaretlidir', (tester) async {
      final service = multiTaskService();
      final router = await pumpApp(tester, service);

      router.go(DeepLink.maintenanceDoneLink(3));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text('Philips Kahve Makinesi'), findsOneWidget);
      expect(find.text('Hangi bakımı yaptınız?'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNWidgets(3));
      expect(isChecked(tester, 'Çöp haznesi temizliği'), isTrue);
      expect(isChecked(tester, 'Demlik temizliği'), isFalse);
      expect(isChecked(tester, 'Kireç çözme'), isFalse);
      expect(find.text('Kaydet (1)'), findsOneWidget);

      // Seçim beklenirken hiçbir şey kaydedilmez ve ekran kendiliğinden kapanmaz.
      await tester.pump(const Duration(seconds: 30));
      expect(service.selections, isEmpty);
      expect(find.text('Hangi bakımı yaptınız?'), findsOneWidget);
    });

    testWidgets('en gecikmiş görev en üstte, durumları gün olarak gösterir', (tester) async {
      final router = await pumpApp(tester, multiTaskService());

      router.go(DeepLink.maintenanceDoneLink(3));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      final titles = tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .map((c) => (c.title as Text).data)
          .toList();
      expect(titles, ['Çöp haznesi temizliği', 'Demlik temizliği', 'Kireç çözme']);
      expect(find.textContaining('3 gün gecikti'), findsOneWidget);
      expect(find.textContaining('6 gün sonra'), findsOneWidget);
      expect(find.textContaining('55 gün sonra'), findsOneWidget);
    });

    testWidgets('seçilen görevler kaydedilir, başarı gösterilir ve ana sayfaya dönülür', (tester) async {
      final receipt = MaintenanceReceipt(
        deviceId: 3,
        deviceName: 'Philips Kahve Makinesi',
        outcome: MaintenanceOutcome.recorded,
        recorded: [
          RecordedTask(
            taskId: 12,
            taskName: 'Çöp haznesi temizliği',
            historyId: 21,
            previousCompletedAt: DateTime(2026, 10, 1),
            nextDueDate: DateTime(2026, 11, 4),
          ),
          RecordedTask(
            taskId: 11,
            taskName: 'Kireç çözme',
            historyId: 22,
            previousCompletedAt: DateTime(2026, 9, 1),
            nextDueDate: DateTime(2026, 12, 27),
          ),
        ],
      );
      final service = multiTaskService(selectionReceipt: receipt);
      final router = await pumpApp(tester, service);

      router.go(DeepLink.maintenanceDoneLink(3));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      await tester.tap(find.text('Kireç çözme'));
      await tester.pump();
      expect(isChecked(tester, 'Kireç çözme'), isTrue);
      expect(find.text('Kaydet (2)'), findsOneWidget);

      await tester.tap(find.text('Kaydet (2)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(service.selections, [
        {12, 11},
      ]);
      expect(find.text(successTitle), findsOneWidget);
      expect(find.textContaining('Çöp haznesi temizliği'), findsOneWidget);
      expect(find.textContaining('Kireç çözme'), findsOneWidget);
      expect(find.text('Geri Al'), findsOneWidget);

      await tester.pumpAndSettle(const Duration(seconds: 5));
      expect(find.text(dashboardTitle), findsOneWidget);
    });

    testWidgets('hiçbir görev seçili değilken kaydet düğmesi kapalıdır', (tester) async {
      final service = multiTaskService();
      final router = await pumpApp(tester, service);

      router.go(DeepLink.maintenanceDoneLink(3));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      await tester.tap(find.text('Çöp haznesi temizliği'));
      await tester.pump();

      final button = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Görev seçin'));
      expect(button.onPressed, isNull);
      expect(service.selections, isEmpty);
    });

    testWidgets('"Vazgeç" hiçbir şey kaydetmeden ana sayfaya döner', (tester) async {
      final service = multiTaskService();
      final router = await pumpApp(tester, service);

      router.go(DeepLink.maintenanceDoneLink(3));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();

      expect(service.selections, isEmpty);
      expect(find.text(dashboardTitle), findsOneWidget);
    });
  });

  testWidgets('host içinde yazılmış kısa bağlantı (homecare://bakim/yapildi) da kayıt tetikler', (tester) async {
    final service = FakeIsarService(coffeeMachineReceipt(MaintenanceOutcome.recorded));
    final router = await pumpApp(tester, service);

    router.go('homecare://bakim/yapildi?cihaz=3');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(service.recordedDeviceIds, [3]);
    expect(find.text(successTitle), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('eski web adresli karekod da bakım kaydı tetikler', (tester) async {
    final service = FakeIsarService(coffeeMachineReceipt(MaintenanceOutcome.recorded));
    final router = await pumpApp(tester, service);

    router.go('https://ovarthy-bot.github.io/homecare/device/index.html?id=3');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(service.recordedDeviceIds, [3]);
    expect(find.text(successTitle), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  for (final broken in [
    'homecare://app/bakim/yapildi?cihaz=abc',
    'homecare://app/bakim/yapildi',
    'homecare://app/bilinmeyen/yol',
    'https://example.com/baska/sayfa',
  ]) {
    testWidgets('geçersiz bağlantı ($broken) hata sayfası yerine ana sayfaya düşer ve kayıt açmaz',
        (tester) async {
      final service = FakeIsarService(coffeeMachineReceipt(MaintenanceOutcome.recorded));
      final router = await pumpApp(tester, service);

      router.go(broken);
      await tester.pumpAndSettle();

      expect(service.recordedDeviceIds, isEmpty);
      expect(find.text(dashboardTitle), findsOneWidget);
    });
  }
}
