import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:ui' as ui;
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';

import '../../../data/local/isar_service.dart';
import '../../../data/models/device_categories.dart';
import '../../../data/models/device_model.dart';
import '../../../data/models/task_model.dart';
import '../../../core/deep_link/deep_link.dart';
import '../../../core/services/backend_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../dashboard/presentation/providers/dashboard_providers.dart';
import '../../settings/utils/qr_pdf_generator.dart';
import 'widgets/device_details_card.dart';
import 'widgets/device_notes_card.dart';
import 'widgets/glass_card.dart';
import 'widgets/task_ring_card.dart';

class DeviceDetailScreen extends ConsumerStatefulWidget {
  final int deviceId;

  const DeviceDetailScreen({super.key, required this.deviceId});

  @override
  ConsumerState<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends ConsumerState<DeviceDetailScreen> {
  late final IsarService _isarService;
  DeviceModel? _device;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _isarService = ref.read(isarServiceProvider);
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

  /// Not kutusu sayfa kapanırken de kaydeder; o sırada `ref` kullanılamayacağı için servis önceden alınır.
  Future<void> _saveNotes(String text) async {
    await _isarService.updateDeviceNotes(widget.deviceId, text);
    _device?.notes = text;
    if (mounted) setState(() {});
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

    final device = _device!;
    final tasks = device.tasks.toList()..sort((a, b) => a.daysRemaining.compareTo(b.daysRemaining));

    return Container(
      decoration: const BoxDecoration(gradient: AppTheme.screenGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          actions: [
            IconButton(
              icon: const Icon(Icons.qr_code),
              tooltip: 'Karekod',
              onPressed: _showQrDialog,
            ),
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Düzenle',
              onPressed: () async {
                await context.push('/devices/edit/${widget.deviceId}');
                _loadDevice(); // Reload after edit
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              tooltip: 'Sil',
              onPressed: _deleteDevice,
            ),
          ],
        ),
        body: ListView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).padding.bottom + 32),
          children: [
            _DeviceHeaderCard(device: device),
            const SizedBox(height: 12),
            DeviceDetailsCard(device: device),
            const SizedBox(height: 12),
            DeviceNotesCard(text: device.notes ?? '', onSave: _saveNotes),
            const SizedBox(height: 24),
            Text('Bakım Görevleri', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (tasks.isEmpty)
              GlassCard(
                child: Text(
                  'Bu cihaz için bakım görevi yok. Düzenle düğmesinden ekleyebilirsiniz.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              )
            else
              ..._buildTaskRows(tasks),
          ],
        ),
      ),
    );
  }

  /// Görev kartları yan yana ikişerli dizilir; aynı satırdaki kartlar eşit yüksekliktedir.
  List<Widget> _buildTaskRows(List<TaskModel> tasks) {
    const gap = 12.0;
    return [
      for (var i = 0; i < tasks.length; i += 2)
        Padding(
          padding: EdgeInsets.only(bottom: i + 2 < tasks.length ? gap : 0),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: TaskRingCard(task: tasks[i], onDone: () => _completeTask(tasks[i]))),
                const SizedBox(width: gap),
                Expanded(
                  child: i + 1 < tasks.length
                      ? TaskRingCard(task: tasks[i + 1], onDone: () => _completeTask(tasks[i + 1]))
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
    ];
  }
}

class _DeviceHeaderCard extends StatelessWidget {
  final DeviceModel device;

  const _DeviceHeaderCard({required this.device});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final category = device.category;
    final subtitle = [device.room, if (category != null && category.isNotEmpty) category].join(' · ');

    return GlassCard(
      child: Row(
        children: [
          _DeviceIconTile(device: device),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.titleLarge?.copyWith(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(subtitle, style: theme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Cihaz fotoğrafı varsa onu, yoksa kategori simgesini gösteren degrade kutu.
class _DeviceIconTile extends StatelessWidget {
  final DeviceModel device;

  const _DeviceIconTile({required this.device});

  @override
  Widget build(BuildContext context) {
    final icon = Icon(DeviceCategories.iconFor(device.category), size: 32, color: AppTheme.textPrimary);
    final imagePath = device.imagePath;

    return Container(
      width: 64,
      height: 64,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: AppTheme.accentGradient,
        borderRadius: BorderRadius.circular(18),
      ),
      child: imagePath == null
          ? icon
          : Image.file(
              File(imagePath),
              width: 64,
              height: 64,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => icon,
            ),
    );
  }
}
