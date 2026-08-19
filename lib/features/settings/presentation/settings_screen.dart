import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../dashboard/presentation/providers/dashboard_providers.dart';
import '../../../data/models/settings_model.dart';
import '../utils/qr_pdf_generator.dart';

final settingsProvider = FutureProvider<SettingsModel>((ref) {
  final isarService = ref.watch(isarServiceProvider);
  return isarService.getSettings();
});

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsyncValue = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: settingsAsyncValue.when(
        data: (settings) {
          return ListView(
            children: [
              SwitchListTile(
                title: const Text('Bakım Bildirimleri'),
                subtitle: const Text('Bakım zamanı geldiğinde bildirim al'),
                value: settings.notificationsEnabled,
                onChanged: (val) async {
                  settings.notificationsEnabled = val;
                  final isarService = ref.read(isarServiceProvider);
                  await isarService.updateSettings(settings);
                  ref.invalidate(settingsProvider);
                },
              ),
              ListTile(
                title: const Text('Varsayılan Hatırlatma Süresi (Gün)'),
                subtitle: Text('Bakımdan ${settings.defaultReminderDays} gün önce hatırlat'),
                trailing: const Icon(Icons.edit),
                onTap: () {
                  showDialog(context: context, builder: (_) {
                    final controller = TextEditingController(text: settings.defaultReminderDays.toString());
                    return AlertDialog(
                      title: const Text('Süreyi Değiştir'),
                      content: TextField(
                        controller: controller,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(suffixText: 'gün'),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
                        TextButton(onPressed: () async {
                          final days = int.tryParse(controller.text) ?? 3;
                          settings.defaultReminderDays = days;
                          final isarService = ref.read(isarServiceProvider);
                          await isarService.updateSettings(settings);
                          ref.invalidate(settingsProvider);
                          if (context.mounted) Navigator.pop(context);
                        }, child: const Text('Kaydet')),
                      ],
                    );
                  });
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.print),
                title: const Text('Tüm Karekodları Yazdır (A4)'),
                subtitle: const Text('Tüm cihazların karekodlarını tek bir A4 sayfasına sığdırıp yazdırın.'),
                onTap: () async {
                  final isarService = ref.read(isarServiceProvider);
                  final devices = await isarService.getDevices();
                  if (devices.isNotEmpty) {
                    await QrPdfGenerator.generateAndPrintA4(devices);
                  } else {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Yazdırılacak cihaz bulunamadı.')),
                      );
                    }
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.download),
                title: const Text('Veri Dışa Aktarma'),
                subtitle: const Text('Tüm veritabanını JSON dosyası olarak aktar'),
                onTap: () async {
                  final isarService = ref.read(isarServiceProvider);
                  await isarService.exportDataAsJson();
                },
              ),
              const Divider(),
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Uygulama Hakkında'),
                subtitle: Text('Homecare v1.0.0'),
              )
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Hata: $e')),
      ),
    );
  }
}
