import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../dashboard/presentation/providers/dashboard_providers.dart';
import '../../../data/models/settings_model.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
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
                title: const Text('GitHub Access Token'),
                subtitle: Text(settings.githubToken != null && settings.githubToken!.isNotEmpty ? 'Token kayıtlı' : 'Web senkronizasyonu için gerekli'),
                trailing: const Icon(Icons.edit),
                onTap: () {
                  showDialog(context: context, builder: (_) {
                    final controller = TextEditingController(text: settings.githubToken ?? '');
                    return AlertDialog(
                      title: const Text('GitHub Token'),
                      content: TextField(
                        controller: controller,
                        decoration: const InputDecoration(hintText: 'ghp_...'),
                        obscureText: true,
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
                        TextButton(onPressed: () async {
                          settings.githubToken = controller.text.trim();
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
              ListTile(
                leading: const Icon(Icons.upload),
                title: const Text('Veri İçe Aktarma'),
                subtitle: const Text('Önceden aktarılan JSON dosyasını yükle'),
                onTap: () async {
                  try {
                    final result = await FilePicker.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['json'],
                    );

                    if (result != null && result.isNotEmpty && result.first.path != null) {
                      final file = File(result.first.path!);
                      final jsonString = await file.readAsString();

                      if (!context.mounted) return;
                      
                      final shouldClear = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('İçe Aktarma Seçeneği'),
                          content: const Text(
                              'Mevcut tüm cihazlarınızı silip sadece dosyadakileri mi yüklemek istersiniz, yoksa dosyadakileri mevcut cihazlara eklemek mi istersiniz?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Üstüne Ekle'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Mevcutları Sil', style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                      );

                      if (shouldClear == null) return; // User cancelled

                      final isarService = ref.read(isarServiceProvider);
                      await isarService.importDataFromJson(jsonString, clearExisting: shouldClear);
                      
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Veriler başarıyla içe aktarıldı.')),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('İçe aktarma hatası: $e')),
                      );
                    }
                  }
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
