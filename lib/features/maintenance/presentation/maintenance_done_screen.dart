import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/device_model.dart';
import '../../../data/models/maintenance_receipt.dart';
import '../../../data/models/task_model.dart';
import '../../dashboard/presentation/providers/dashboard_providers.dart';
import '../maintenance_policy.dart';

/// Karekod bağlantısıyla açılır: bakımı soru sormadan kaydeder, kısa bir başarı
/// animasyonu gösterir ve kendiliğinden kapanır.
class MaintenanceDoneScreen extends ConsumerStatefulWidget {
  final int deviceId;

  const MaintenanceDoneScreen({super.key, required this.deviceId});

  @override
  ConsumerState<MaintenanceDoneScreen> createState() => _MaintenanceDoneScreenState();
}

class _MaintenanceDoneScreenState extends ConsumerState<MaintenanceDoneScreen>
    with TickerProviderStateMixin {
  static const _autoCloseAfter = Duration(milliseconds: 3500);

  late final AnimationController _checkController;
  late final AnimationController _closeController;

  MaintenanceReceipt? _receipt;
  bool _loading = true;
  bool _undone = false;
  Object? _error;

  // Birden fazla görevi olan cihazda kullanıcıya gösterilen seçim aşaması.
  DeviceModel? _choosingFor;
  Set<int> _selectedTaskIds = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _checkController = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _closeController = AnimationController(vsync: this, duration: _autoCloseAfter)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _close();
      });
    _record();
  }

  @override
  void dispose() {
    _checkController.dispose();
    _closeController.dispose();
    super.dispose();
  }

  Future<void> _record() async {
    try {
      final service = ref.read(isarServiceProvider);
      final receipt = await service.recordMaintenanceViaQr(widget.deviceId);

      if (receipt?.outcome == MaintenanceOutcome.needsSelection) {
        final device = await service.getDeviceById(widget.deviceId);
        if (!mounted) return;
        if (device == null) return _showReceipt(null);
        setState(() {
          _choosingFor = device;
          // Zamanı gelmiş görevler önceden işaretli gelir; yaygın durumda tek dokunuş yeter.
          _selectedTaskIds = MaintenancePolicy.tasksToRecord(device.tasks).map((t) => t.id).toSet();
          _loading = false;
        });
        return;
      }

      if (!mounted) return;
      _showReceipt(receipt);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _saveSelection() async {
    if (_saving || _selectedTaskIds.isEmpty) return;
    setState(() => _saving = true);

    try {
      final receipt = await ref
          .read(isarServiceProvider)
          .recordSelectedTasks(widget.deviceId, _selectedTaskIds);
      if (!mounted) return;
      _showReceipt(receipt);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _saving = false;
      });
    }
  }

  /// Kayıt sonucunu gösterir; başarılıysa animasyonu ve otomatik kapanmayı başlatır.
  void _showReceipt(MaintenanceReceipt? receipt) {
    setState(() {
      _receipt = receipt;
      _choosingFor = null;
      _saving = false;
      _loading = false;
    });

    final succeeded = receipt != null &&
        (receipt.outcome == MaintenanceOutcome.recorded ||
            receipt.outcome == MaintenanceOutcome.alreadyRecorded);
    if (!succeeded) return;
    HapticFeedback.mediumImpact();
    _checkController.forward();
    _closeController.forward();
  }

  Future<void> _undo() async {
    final receipt = _receipt;
    if (receipt == null || _undone) return;

    _closeController.stop();
    try {
      await ref.read(isarServiceProvider).undoMaintenance(receipt);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
      return;
    }
    if (!mounted) return;
    setState(() => _undone = true);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    _close();
  }

  void _close() {
    if (mounted) context.go('/');
  }

  /// Karekodla açıldıysa geri gidecek yığın yoktur; önce ana sayfaya, sonra detaya git.
  void _openDevice() {
    final router = GoRouter.of(context);
    router.go('/');
    router.push('/device/${widget.deviceId}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: _buildContent(context),
                ),
              ),
            ),
            AnimatedBuilder(
              animation: _closeController,
              builder: (context, _) => LinearProgressIndicator(
                value: _closeController.isAnimating ? 1 - _closeController.value : 0,
                minHeight: 3,
                backgroundColor: Colors.transparent,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_loading) return const CircularProgressIndicator();

    if (_error != null) {
      return _Message(
        icon: Icons.error_outline,
        color: AppTheme.statusOverdue,
        title: 'Bakım kaydedilemedi',
        subtitle: '$_error',
        actions: [TextButton(onPressed: _close, child: const Text('Ana Sayfa'))],
      );
    }

    final choosingFor = _choosingFor;
    if (choosingFor != null) return _buildChooser(context, choosingFor);

    final receipt = _receipt;
    if (receipt == null) {
      return _Message(
        icon: Icons.search_off,
        color: AppTheme.statusUpcoming,
        title: 'Cihaz bulunamadı',
        subtitle: 'Bu karekoda ait cihaz bu telefonda kayıtlı değil. Silinmiş ya da '
            'başka bir telefonda oluşturulmuş olabilir.',
        actions: [TextButton(onPressed: _close, child: const Text('Ana Sayfa'))],
      );
    }

    if (_undone) {
      return _Message(
        icon: Icons.undo,
        color: AppTheme.textSecondary,
        title: 'Kayıt geri alındı',
        subtitle: '${receipt.deviceName} için bakım kaydı silindi.',
      );
    }

    switch (receipt.outcome) {
      case MaintenanceOutcome.needsSelection:
        // Seçim aşaması `_choosingFor` ile ayrıca gösterilir; makbuz olarak buraya gelmez.
        return const SizedBox.shrink();
      case MaintenanceOutcome.noTasks:
        return _Message(
          icon: Icons.playlist_add,
          color: AppTheme.statusUpcoming,
          title: '${receipt.deviceName} için bakım görevi yok',
          subtitle: 'Karekodla kayıt yapılabilmesi için cihaza en az bir bakım görevi ekleyin.',
          actions: [
            TextButton(onPressed: _close, child: const Text('Ana Sayfa')),
            TextButton(onPressed: _openDevice, child: const Text('Cihaza Git')),
          ],
        );
      case MaintenanceOutcome.alreadyRecorded:
        return _buildSuccess(
          context,
          receipt,
          color: AppTheme.infoWarranty,
          title: 'Bu bakım az önce kaydedilmişti',
        );
      case MaintenanceOutcome.recorded:
        return _buildSuccess(
          context,
          receipt,
          color: AppTheme.statusNormal,
          title: '${receipt.deviceName} Bakımı Kaydedildi!',
        );
    }
  }

  Widget _buildChooser(BuildContext context, DeviceModel device) {
    final tasks = device.tasks.toList()
      ..sort((a, b) => a.daysRemaining.compareTo(b.daysRemaining));

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            device.name,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Hangi bakımı yaptınız?',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final task in tasks)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: CheckboxListTile(
                      value: _selectedTaskIds.contains(task.id),
                      onChanged: _saving
                          ? null
                          : (checked) => setState(() {
                                if (checked == true) {
                                  _selectedTaskIds.add(task.id);
                                } else {
                                  _selectedTaskIds.remove(task.id);
                                }
                              }),
                      title: Text(task.name),
                      subtitle: _TaskStatus(task: task),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _selectedTaskIds.isEmpty || _saving ? null : _saveSelection,
              child: Text(_selectedTaskIds.isEmpty ? 'Görev seçin' : 'Kaydet (${_selectedTaskIds.length})'),
            ),
          ),
          TextButton(onPressed: _saving ? null : _close, child: const Text('Vazgeç')),
        ],
      ),
    );
  }

  Widget _buildSuccess(
    BuildContext context,
    MaintenanceReceipt receipt, {
    required Color color,
    required String title,
  }) {
    final dateFormat = DateFormat('d MMM y', 'tr_TR');
    final nextDue = {for (final r in receipt.recorded) r.taskName: r.nextDueDate};

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _checkController,
          builder: (context, _) => CustomPaint(
            size: const Size(112, 112),
            painter: _CheckPainter(progress: _checkController.value, color: color),
          ),
        ),
        const SizedBox(height: 28),
        Semantics(
          liveRegion: true,
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        const SizedBox(height: 20),
        for (final name in receipt.taskNames)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              nextDue[name] == null ? name : '$name  ·  Sonraki: ${dateFormat.format(nextDue[name]!)}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppTheme.textSecondary),
            ),
          ),
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            if (receipt.canUndo)
              TextButton.icon(
                onPressed: _undo,
                icon: const Icon(Icons.undo),
                label: const Text('Geri Al'),
              ),
            TextButton(onPressed: _openDevice, child: const Text('Cihaz Detayı')),
          ],
        ),
      ],
    );
  }
}

/// "2 gün gecikti · Periyot: 7 gün" gibi, gecikmişse kırmızı, yaklaşıyorsa sarı.
class _TaskStatus extends StatelessWidget {
  final TaskModel task;

  const _TaskStatus({required this.task});

  @override
  Widget build(BuildContext context) {
    final days = task.daysRemaining;
    final String status;
    final Color color;
    if (days < 0) {
      status = '${-days} gün gecikti';
      color = AppTheme.statusOverdue;
    } else if (days == 0) {
      status = 'Bugün';
      color = AppTheme.statusUpcoming;
    } else {
      status = '$days gün sonra';
      color = days <= 14 ? AppTheme.statusUpcoming : AppTheme.statusNormal;
    }

    return Text('$status · Periyot: ${task.intervalDays} gün', style: TextStyle(color: color));
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  const _Message({
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 72, color: color),
        const SizedBox(height: 24),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 12),
          Text(
            subtitle!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 24),
          Wrap(alignment: WrapAlignment.center, spacing: 8, children: actions),
        ],
      ],
    );
  }
}

/// Önce halka, sonra onay işareti çizilir. `progress` 0..1.
class _CheckPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _CheckPainter({required this.progress, required this.color});

  static const _ringShare = 0.6;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = size.width * 0.07;

    final inset = paint.strokeWidth / 2;
    final ring = Path()..addOval(Rect.fromLTWH(inset, inset, size.width - 2 * inset, size.height - 2 * inset));
    final ringProgress = (progress / _ringShare).clamp(0.0, 1.0);
    _drawPartial(canvas, ring, ringProgress, paint);

    final check = Path()
      ..moveTo(size.width * 0.29, size.height * 0.53)
      ..lineTo(size.width * 0.44, size.height * 0.68)
      ..lineTo(size.width * 0.72, size.height * 0.37);
    final checkProgress = ((progress - _ringShare) / (1 - _ringShare)).clamp(0.0, 1.0);
    _drawPartial(canvas, check, checkProgress, paint);
  }

  void _drawPartial(Canvas canvas, Path path, double fraction, Paint paint) {
    if (fraction <= 0) return;
    for (final PathMetric metric in path.computeMetrics()) {
      canvas.drawPath(metric.extractPath(0, metric.length * fraction), paint);
    }
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.progress != progress || old.color != color;
}
