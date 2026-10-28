import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/routing/app_router.dart';
import 'features/dashboard/presentation/providers/dashboard_providers.dart';
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

class HomecareApp extends ConsumerStatefulWidget {
  const HomecareApp({super.key});

  @override
  ConsumerState<HomecareApp> createState() => _HomecareAppState();
}

class _HomecareAppState extends ConsumerState<HomecareApp> with WidgetsBindingObserver {
  /// Uygulama art arda öne gelse de ara depo bu süreden sık sorgulanmaz.
  static const _minSyncGap = Duration(seconds: 30);

  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  DateTime? _lastSync;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncWebRecords());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _syncWebRecords();
  }

  /// Uygulaması olmayan telefonlardan gelen bakım kayıtlarını sessizce alır; yeni kayıt varsa haber verir.
  Future<void> _syncWebRecords() async {
    final last = _lastSync;
    if (last != null && DateTime.now().difference(last) < _minSyncGap) return;
    _lastSync = DateTime.now();

    try {
      final result = await ref.read(isarServiceProvider).syncWithBackend();
      if (result != null && result.imported > 0) {
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('Web\'den ${result.imported} bakım kaydı eklendi.')),
        );
      }
    } catch (e) {
      // Ağ yok ya da ara depo kapalı: bir sonraki açılışta yeniden denenir.
      debugPrint('Web kayıtları alınamadı: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      scaffoldMessengerKey: _messengerKey,
      title: 'Homecare',
      theme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark, // Uygulama her zaman karanlık tema ile çalışacak
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
