import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../dashboard/presentation/providers/dashboard_providers.dart';
import '../../../core/services/backend_service.dart';
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

  Future<void> _editTextSetting(
    BuildContext context,
    WidgetRef ref, {
    required SettingsModel settings,
    required String title,
    required String hint,
    required String helper,
    required String? current,
    required String? Function(String value) validate,
    required void Function(String? value) apply,
    bool obscure = false,
  }) {
    final controller = TextEditingController(text: current ?? '');
    String? error;

    return showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            obscureText: obscure,
            autocorrect: false,
            decoration: InputDecoration(
              hintText: hint,
              helperText: helper,
              helperMaxLines: 4,
              errorText: error,
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('İptal')),
            TextButton(
              onPressed: () async {
                final value = controller.text.trim();
                final problem = value.isEmpty ? null : validate(value);
                if (problem != null) {
                  setState(() => error = problem);
                  return;
                }
                apply(value.isEmpty ? null : value);
                await ref.read(isarServiceProvider).updateSettings(settings);
                ref.invalidate(settingsProvider);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _syncNow(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Eşitleniyor...')));

    String message;
    try {
      final result = await ref.read(isarServiceProvider).syncWithBackend();
      message = result?.summary ?? 'Ara depo ayarlanmamış.';
    } on BackendException catch (e) {
      message = 'Eşitlenemedi: ${e.message}';
    } catch (e) {
      message = 'Eşitlenemedi: $e';
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

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
                leading: const Icon(Icons.cloud_sync_outlined),
                title: const Text('Web\'den Bakım Kaydı'),
                subtitle: Text(
                  BackendService.isConfigured(settings)
                      ? 'Açık: uygulaması olmayan telefonlar karekodu okutup bakım kaydı bırakabilir.'
                      : 'Uygulaması olmayan telefonlardan bakım kaydı için aşağıdaki iki alanı doldurun '
                          '(kurulum: backend/apps-script/README.md).',
                ),
              ),
              ListTile(
                title: const Text('Eşitleme Adresi'),
                subtitle: Text(
                  (settings.backendUrl ?? '').isEmpty ? 'Ayarlanmadı' : settings.backendUrl!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.edit),
                onTap: () => _editTextSetting(
                  context,
                  ref,
                  settings: settings,
                  title: 'Eşitleme Adresi',
                  hint: 'https://script.google.com/macros/s/.../exec',
                  helper: 'Google Apps Script web uygulamasının adresi. docs/config.js içindekiyle aynı olmalı.',
                  current: settings.backendUrl,
                  validate: (value) => value.startsWith('https://') ? null : 'Adres https:// ile başlamalı',
                  apply: (value) => settings.backendUrl = value,
                ),
              ),
              ListTile(
                title: const Text('Eşitleme Anahtarı'),
                subtitle: Text((settings.syncKey ?? '').isEmpty ? 'Ayarlanmadı' : 'Kayıtlı'),
                trailing: const Icon(Icons.edit),
                onTap: () => _editTextSetting(
                  context,
                  ref,
                  settings: settings,
                  title: 'Eşitleme Anahtarı',
                  hint: 'Ara depodaki SECRET ile aynı',
                  helper: 'Anahtarı değiştirirseniz basılı karekodlar geçersiz olur; yeniden yazdırmanız gerekir.',
                  current: settings.syncKey,
                  obscure: true,
                  validate: (value) => value.length >= 12 ? null : 'En az 12 karakter olmalı',
                  apply: (value) => settings.syncKey = value,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.sync),
                title: const Text('Şimdi Eşitle'),
                subtitle: const Text('Bekleyen web kayıtlarını al, cihazları ara depoya gönder'),
                enabled: BackendService.isConfigured(settings),
                onTap: () => _syncNow(context, ref),
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
                    await QrPdfGenerator.generateAndPrintA4(devices, settings: settings);
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
