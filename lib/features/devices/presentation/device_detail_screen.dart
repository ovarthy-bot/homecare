import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:ui' as ui;
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';

import '../../../data/models/device_categories.dart';
import '../../../data/models/device_model.dart';
import '../../../data/models/task_model.dart';
import '../../../core/deep_link/deep_link.dart';
import '../../../core/services/backend_service.dart';
import '../../dashboard/presentation/providers/dashboard_providers.dart';
import '../../settings/utils/qr_pdf_generator.dart';

class DeviceDetailScreen extends ConsumerStatefulWidget {
  final int deviceId;

  const DeviceDetailScreen({super.key, required this.deviceId});

  @override
  ConsumerState<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends ConsumerState<DeviceDetailScreen> {
  DeviceModel? _device;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDevice();
  }

  Future<void> _loadDevice() async {
    final isarService = ref.read(isarServiceProvider);
    _device = await isarService.getDeviceById(widget.deviceId);
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _deleteDevice() async {
    final isarService = ref.read(isarServiceProvider);
    await isarService.deleteDevice(widget.deviceId);
    if (mounted) {
      context.pop();
    }
  }

  Future<void> _completeTask(TaskModel task) async {
    final isarService = ref.read(isarServiceProvider);
    
    await isarService.logTaskCompletion(_device!.id, _device!.name, task.name);
    
    task.lastCompletedAt = DateTime.now();
    await isarService.saveDeviceWithTasks(_device!, _device!.tasks.toList());
    
    _loadDevice();
  }

  String _calculateUsageTime(DateTime purchaseDate) {
    final now = DateTime.now();
    int years = now.year - purchaseDate.year;
    int months = now.month - purchaseDate.month;
    
    if (months < 0) {
      years--;
      months += 12;
    }
    
    if (years > 0 && months > 0) return '$years Yıl $months Ay';
    if (years > 0) return '$years Yıl';
    if (months > 0) return '$months Ay';
    return '1 Aydan az';
  }

  Future<void> _showQrDialog() async {
    final settings = await ref.read(isarServiceProvider).getSettings();
    if (!mounted) return;
    final qrKey = BackendService.qrKeyFor(settings, _device!.id);

    showDialog(
      context: context,
      builder: (context) {
        final qrData = DeepLink.qrData(_device!.id, key: qrKey);
        return AlertDialog(
          title: Text(_device!.name),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 250,
                height: 250,
                child: QrImageView(
                  data: qrData,
                  version: QrVersions.auto,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                qrKey == null
                    ? 'Yazdırıp cihazın yanına yapıştırın. Uygulamanın tarayıcısıyla okutunca bakım '
                        'otomatik kaydedilir; telefonun kamerasıyla okutunca cihaz sayfası açılır.'
                    : 'Yazdırıp cihazın yanına yapıştırın. Uygulamanın tarayıcısıyla okutunca bakım '
                        'otomatik kaydedilir. Telefonun kamerasıyla okutan, uygulaması olmasa da '
                        'cihaz sayfasından bakım kaydı bırakabilir.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => context.pop(),
              child: const Text('Kapat'),
            ),
            OutlinedButton.icon(
              onPressed: () => QrPdfGenerator.generateAndPrintA4([_device!], settings: settings),
              icon: const Icon(Icons.print),
              label: const Text('Yazdır'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                final qrValidationResult = QrValidator.validate(
                  data: qrData,
                  version: QrVersions.auto,
                  errorCorrectionLevel: QrErrorCorrectLevel.L,
                );
                if (qrValidationResult.status == QrValidationStatus.valid) {
                  final qrCode = qrValidationResult.qrCode!;
                  final painter = QrPainter.withQr(
                    qr: qrCode,
                    gapless: true,
                  );
                  final picData = await painter.toImageData(2048, format: ui.ImageByteFormat.png);
                  if (picData != null) {
                    final directory = await getTemporaryDirectory();
                    final file = File('${directory.path}/qr_${widget.deviceId}.png');
                    await file.writeAsBytes(picData.buffer.asUint8List());
                    // ignore: deprecated_member_use
                    await Share.shareXFiles([XFile(file.path)], text: '${_device!.name} Karekodu');
                  }
                }
              },
              icon: const Icon(Icons.share),
              label: const Text('Paylaş'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    
    if (_device == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Hata')),
        body: const Center(child: Text('Cihaz bulunamadı')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_device!.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code),
            onPressed: _showQrDialog,
          ),
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () async {
              await context.push('/devices/edit/${widget.deviceId}');
              _loadDevice(); // Reload after edit
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: _deleteDevice,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Bulunduğu Oda: ${_device!.room}', style: Theme.of(context).textTheme.titleMedium),
          if (_device!.category != null && _device!.category!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(DeviceCategories.iconFor(_device!.category), size: 18),
                const SizedBox(width: 8),
                Text(_device!.category!, style: Theme.of(context).textTheme.bodyLarge),
              ],
            ),
          ],
          const SizedBox(height: 16),
          
          if (_device!.purchaseDate != null)
            Text('Kullanım Süresi: ${_calculateUsageTime(_device!.purchaseDate!)}', style: Theme.of(context).textTheme.bodyLarge),
            
          if (_device!.serviceInfo != null && _device!.serviceInfo!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Yetkili Servis: ${_device!.serviceInfo}', style: Theme.of(context).textTheme.bodyMedium),
          ],
          
          if (_device!.notes != null && _device!.notes!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Notlar: ${_device!.notes}', style: Theme.of(context).textTheme.bodyMedium),
          ],

          const SizedBox(height: 32),
          Text('Bakım Görevleri', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          
          ..._device!.tasks.map((task) {
            final days = task.daysRemaining;
            String status = '';
            Color color = Colors.grey;
            if (days < 0) {
              status = '${-days} gün gecikti';
              color = Colors.red;
            } else {
              status = '$days gün sonra';
              color = Colors.green;
            }

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(task.name),
                subtitle: Text('Periyot: ${task.intervalDays} gün\nDurum: $status', style: TextStyle(color: color)),
                trailing: IconButton(
                  icon: const Icon(Icons.check_circle_outline, color: Colors.green, size: 32),
                  tooltip: 'Yapıldı İşaretle',
                  onPressed: () => _completeTask(task),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
