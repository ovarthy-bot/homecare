import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:homecare/data/models/device_model.dart';
import 'package:homecare/data/models/history_model.dart';
import 'package:homecare/features/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:homecare/features/history/presentation/history_screen.dart';

HistoryModel log(String task, DateTime at, {String? source}) {
  return HistoryModel()
    ..deviceName = 'Philips Kahve Makinesi'
    ..taskName = task
    ..completedAt = at
    ..source = source;
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  testWidgets('web\'den gelen kayıt işaretlenir, uygulamadaki işaretlenmez', (tester) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          historyProvider.overrideWith((ref) => Stream.value([
                log('Kireç çözme', now, source: HistoryModel.sourceWeb),
                log('Demlik temizliği', now.subtract(const Duration(minutes: 5))),
              ])),
          devicesProvider.overrideWith((ref) => Stream.value(<DeviceModel>[])),
        ],
        child: const MaterialApp(home: HistoryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Kireç çözme yapıldı'), findsOneWidget);
    expect(find.text('Demlik temizliği yapıldı'), findsOneWidget);
    expect(find.text('Web\'den'), findsOneWidget);
    expect(find.byIcon(Icons.public), findsOneWidget);
  });
}
