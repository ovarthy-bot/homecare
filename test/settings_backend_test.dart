import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:homecare/core/services/backend_service.dart';
import 'package:homecare/data/local/isar_service.dart';
import 'package:homecare/data/models/settings_model.dart';
import 'package:homecare/features/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:homecare/features/settings/presentation/settings_screen.dart';

class FakeSettingsService implements IsarService {
  SettingsModel settings;
  WebSyncResult? syncResult;
  Object? syncError;
  int syncCalls = 0;
  int saves = 0;

  FakeSettingsService(this.settings);

  @override
  Future<SettingsModel> getSettings() async => settings;

  @override
  Future<void> updateSettings(SettingsModel updated) async {
    settings = updated;
    saves++;
  }

  @override
  Future<WebSyncResult?> syncWithBackend() async {
    syncCalls++;
    if (syncError != null) throw syncError!;
    return syncResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const validUrl = 'https://script.google.com/macros/s/abc/exec';

Future<void> pumpSettings(WidgetTester tester, FakeSettingsService service) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [isarServiceProvider.overrideWithValue(service)],
      child: const MaterialApp(home: SettingsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

bool isEnabled(WidgetTester tester, String title) {
  return tester.widget<ListTile>(find.widgetWithText(ListTile, title)).enabled;
}

Future<void> enterAndSave(WidgetTester tester, String value) async {
  await tester.enterText(find.byType(TextField), value);
  await tester.tap(find.text('Kaydet'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('ara depo kurulu değilken "Şimdi Eşitle" kapalıdır', (tester) async {
    await pumpSettings(tester, FakeSettingsService(SettingsModel()));

    expect(isEnabled(tester, 'Şimdi Eşitle'), isFalse);
    expect(find.text('Ayarlanmadı'), findsNWidgets(2), reason: 'adres ve anahtar');
  });

  testWidgets('adres ve anahtar kaydedilince "Şimdi Eşitle" açılır', (tester) async {
    final service = FakeSettingsService(SettingsModel());
    await pumpSettings(tester, service);

    await tester.tap(find.text('Eşitleme Adresi'));
    await tester.pumpAndSettle();
    await enterAndSave(tester, validUrl);
    expect(service.settings.backendUrl, validUrl);
    expect(isEnabled(tester, 'Şimdi Eşitle'), isFalse, reason: 'anahtar hâlâ yok');

    await tester.tap(find.text('Eşitleme Anahtarı'));
    await tester.pumpAndSettle();
    await enterAndSave(tester, 'uzun-gizli-anahtar');
    expect(service.settings.syncKey, 'uzun-gizli-anahtar');

    expect(isEnabled(tester, 'Şimdi Eşitle'), isTrue);
    expect(find.text('Kayıtlı'), findsOneWidget);
  });

  testWidgets('https olmayan adres ve kısa anahtar kaydedilmez, hata gösterilir', (tester) async {
    final service = FakeSettingsService(SettingsModel());
    await pumpSettings(tester, service);

    await tester.tap(find.text('Eşitleme Adresi'));
    await tester.pumpAndSettle();
    await enterAndSave(tester, 'http://script.google.com/exec');
    expect(find.text('Adres https:// ile başlamalı'), findsOneWidget);
    expect(service.saves, 0);
    await tester.tap(find.text('İptal'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Eşitleme Anahtarı'));
    await tester.pumpAndSettle();
    await enterAndSave(tester, 'kisa');
    expect(find.text('En az 12 karakter olmalı'), findsOneWidget);
    expect(service.saves, 0);
    expect(service.settings.syncKey, isNull);
  });

  testWidgets('alan boşaltılıp kaydedilirse ayar silinir', (tester) async {
    final service = FakeSettingsService(SettingsModel()..backendUrl = validUrl);
    await pumpSettings(tester, service);

    await tester.tap(find.text('Eşitleme Adresi'));
    await tester.pumpAndSettle();
    await enterAndSave(tester, '');

    expect(service.settings.backendUrl, isNull);
    expect(find.text('Ayarlanmadı'), findsNWidgets(2));
  });

  testWidgets('"Şimdi Eşitle" sonucu özet olarak gösterir', (tester) async {
    final service = FakeSettingsService(
      SettingsModel()
        ..backendUrl = validUrl
        ..syncKey = 'uzun-gizli-anahtar',
    )..syncResult = const WebSyncResult(imported: 2, unmatched: 1, pushedDevices: 5);
    await pumpSettings(tester, service);

    await tester.tap(find.text('Şimdi Eşitle'));
    await tester.pumpAndSettle();

    expect(service.syncCalls, 1);
    expect(
      find.text('2 web kaydı eklendi · 1 kayıt eşleşmedi (cihaz silinmiş olabilir) · 5 cihaz güncellendi'),
      findsOneWidget,
    );
  });

  testWidgets('eşitleme hatası kullanıcıya anlaşılır biçimde gösterilir', (tester) async {
    final service = FakeSettingsService(
      SettingsModel()
        ..backendUrl = validUrl
        ..syncKey = 'uzun-gizli-anahtar',
    )..syncError = const BackendException('Eşitleme anahtarı, ara depodaki SECRET ile aynı değil.');
    await pumpSettings(tester, service);

    await tester.tap(find.text('Şimdi Eşitle'));
    await tester.pumpAndSettle();

    expect(find.text('Eşitlenemedi: Eşitleme anahtarı, ara depodaki SECRET ile aynı değil.'), findsOneWidget);
  });

  group('WebSyncResult.summary', () {
    test('cihazlar gönderilemediyse nedenini söyler', () {
      const result = WebSyncResult(imported: 0, unmatched: 0, pushedDevices: 0, pushError: 'Ara depoya ulaşılamadı.');

      expect(result.summary, 'Yeni web kaydı yok · cihazlar gönderilemedi: Ara depoya ulaşılamadı.');
    });

    test('web\'de güncellenen notları da sayar', () {
      const result = WebSyncResult(imported: 1, notesUpdated: 2, unmatched: 0, pushedDevices: 5);

      expect(result.summary, '1 web kaydı eklendi · 2 not güncellendi · 5 cihaz güncellendi');
    });
  });
}
