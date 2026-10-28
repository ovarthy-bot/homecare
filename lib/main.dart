import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';

import 'core/services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('tr_TR');
  await NotificationService().init();
  runApp(
    const ProviderScope(
      child: HomecareApp(),
    ),
  );
}

class HomecareApp extends ConsumerWidget {
  const HomecareApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Homecare',
      theme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark, // Uygulama her zaman karanlık tema ile çalışacak
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
