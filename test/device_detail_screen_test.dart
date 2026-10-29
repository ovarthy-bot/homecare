import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'package:homecare/data/local/isar_service.dart';
import 'package:homecare/data/models/device_model.dart';
import 'package:homecare/data/models/task_model.dart';
import 'package:homecare/features/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:homecare/features/devices/presentation/device_detail_screen.dart';

import 'support/test_devices.dart';

/// Isar'ı açmadan cihaz sayfasının çağırdığı metotları kaydeden sahte servis.
class _FakeIsarService implements IsarService {
  final DeviceModel device;
  final savedNotes = <String>[];
  final loggedTasks = <String>[];

  _FakeIsarService(this.device);

  @override
  Future<DeviceModel?> getDeviceById(int id) async => device;

  @override
  Future<void> updateDeviceNotes(int deviceId, String notes) async => savedNotes.add(notes);

  @override
  Future<void> logTaskCompletion(int deviceId, String deviceName, String taskName) async =>
      loggedTasks.add(taskName);

  @override
  Future<void> saveDeviceWithTasks(DeviceModel device, List<TaskModel> tasks) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Biri gecikmiş, biri zamanı gelmemiş iki görevli yazıcı.
DeviceModel printer() {
  final now = DateTime.now();
  return TestDevice([
    taskOf(1, 'Kartuş temizleme', intervalDays: 30, completedDaysAgo: 40),
    taskOf(2, 'Derin temizleme', intervalDays: 90, completedDaysAgo: 10),
  ])
    ..id = 7
    ..name = 'Epson yazıcı'
    ..room = 'Ebeveyn odası'
    ..category = 'Elektronik'
    ..modelInfo = 'Epson EcoTank L3250'
    ..price = 8489
    ..purchaseDate = DateTime(now.year - 1, now.month, 1)
    ..warrantyMonths = 24
    ..notes = 'Düzenli kullanım önerilir.';
}

Future<_FakeIsarService> _pumpScreen(WidgetTester tester, {DeviceModel? device}) async {
  // Telefon boyutu: kartlar dar genişlikte de taşmadan sığmalı.
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final service = _FakeIsarService(device ?? printer());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [isarServiceProvider.overrideWithValue(service)],
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: const DeviceDetailScreen(deviceId: 7),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return service;
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  group('Ayrıntılar', () {
    testWidgets('satın alma ve garanti varsayılan olarak gizlidir', (tester) async {
      final device = printer();
      await _pumpScreen(tester, device: device);

      expect(find.text('Epson yazıcı'), findsOneWidget);
      expect(find.text('Ayrıntılar'), findsOneWidget);
      expect(find.text('Satın alma'), findsNothing);
      expect(find.text('Garanti'), findsNothing);
      expect(find.text('8.489 TL'), findsNothing);
      expect(find.text('Epson EcoTank L3250'), findsNothing);
    });

    testWidgets('düğmeye basınca model, fiyat, satın alma, garanti ve notlar görünür', (tester) async {
      final device = printer();
      await _pumpScreen(tester, device: device);

      await tester.tap(find.text('Ayrıntılar'));
      await tester.pumpAndSettle();

      final date = DateFormat('dd.MM.yyyy');
      expect(find.text('Epson EcoTank L3250'), findsOneWidget);
      expect(find.text('8.489 TL'), findsOneWidget);
      expect(find.text(date.format(device.purchaseDate!)), findsOneWidget);
      expect(find.textContaining('kaldı'), findsOneWidget);
      expect(find.text('Bitiş: ${date.format(device.warrantyEndDate!)}'), findsOneWidget);
      expect(find.text('Düzenli kullanım önerilir.'), findsNWidgets(2)); // ayrıntı satırı + not kutusu
      expect(find.text('Yetkili servis'), findsNothing, reason: 'servis bilgisi girilmemişse satır yok');

      await tester.tap(find.text('Ayrıntılar'));
      await tester.pumpAndSettle();
      expect(find.text('8.489 TL'), findsNothing);
    });

    testWidgets('yetkili servis bilgisi varsa ayrıntılarda gösterilir', (tester) async {
      await _pumpScreen(tester, device: printer()..serviceInfo = 'Merkez servis 0850 000 00 00');

      await tester.tap(find.text('Ayrıntılar'));
      await tester.pumpAndSettle();

      expect(find.text('Yetkili servis'), findsOneWidget);
      expect(find.text('Merkez servis 0850 000 00 00'), findsOneWidget);
    });

    testWidgets('girilmemiş bilgiler "—" ile gösterilir', (tester) async {
      final device = TestDevice([])
        ..id = 7
        ..name = 'Boş cihaz'
        ..room = 'Salon';
      await _pumpScreen(tester, device: device);

      await tester.tap(find.text('Ayrıntılar'));
      await tester.pumpAndSettle();

      expect(find.text('—'), findsNWidgets(4)); // model, fiyat, satın alma, garanti
      expect(find.text('Not eklenmemiş'), findsOneWidget);
    });
  });

  group('Not kutusu', () {
    testWidgets('yazmaya ara verilince kendiliğinden kaydeder', (tester) async {
      final service = await _pumpScreen(tester);

      await tester.enterText(find.byType(TextField), '  Filtre: F-12  ');
      await tester.pump(const Duration(milliseconds: 500));
      expect(service.savedNotes, isEmpty);
      expect(find.text('Yazıyorsunuz…'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(service.savedNotes, ['Filtre: F-12']);
      expect(find.text('Kaydedildi'), findsOneWidget);
    });

    testWidgets('kaydedilen not ayrıntılarda da görünür', (tester) async {
      await _pumpScreen(tester);

      await tester.enterText(find.byType(TextField), 'Yeni not');
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pump();

      await tester.tap(find.text('Ayrıntılar'));
      await tester.pumpAndSettle();
      expect(find.text('Yeni not'), findsNWidgets(2));
    });

    testWidgets('sayfa bekleme süresi dolmadan kapanırsa yazılan not yine de kaydedilir', (tester) async {
      final service = await _pumpScreen(tester);

      await tester.enterText(find.byType(TextField), 'Acele not');
      await tester.pumpWidget(const SizedBox());

      expect(service.savedNotes, ['Acele not']);
    });

    testWidgets('değişiklik yoksa kaydetmez', (tester) async {
      final service = await _pumpScreen(tester);

      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());

      expect(service.savedNotes, isEmpty);
    });
  });

  group('Bakım görevleri', () {
    testWidgets('en acil görev önce gelir ve kalan gün gösterilir', (tester) async {
      await _pumpScreen(tester);

      final overdue = tester.getTopLeft(find.text('Kartuş temizleme'));
      final later = tester.getTopLeft(find.text('Derin temizleme'));
      expect(overdue.dx, lessThan(later.dx)); // aynı satırda, acil olan solda
      expect(find.text('Gecikti'), findsOneWidget);
      expect(find.text('Kalan gün'), findsOneWidget);
      expect(find.text('30 günde bir'), findsOneWidget);
    });

    testWidgets('"Yaptım" bakımı kaydeder', (tester) async {
      final service = await _pumpScreen(tester);

      await tester.ensureVisible(find.text('Yaptım').last);
      await tester.tap(find.text('Yaptım').last);
      await tester.pumpAndSettle();

      expect(service.loggedTasks, ['Derin temizleme']);
    });

    testWidgets('görevi olmayan cihazda açıklama gösterilir', (tester) async {
      final device = TestDevice([])
        ..id = 7
        ..name = 'Boş cihaz'
        ..room = 'Salon';
      await _pumpScreen(tester, device: device);

      expect(find.textContaining('bakım görevi yok'), findsOneWidget);
      expect(find.text('Yaptım'), findsNothing);
    });
  });
}
