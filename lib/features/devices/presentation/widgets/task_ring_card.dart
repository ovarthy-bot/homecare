import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../data/models/task_model.dart';

/// Bakım görevi kartı: kalan günü halkada gösterir, "Yaptım" ile bakım kaydedilir.
class TaskRingCard extends StatelessWidget {
  final TaskModel task;
  final VoidCallback onDone;

  const TaskRingCard({super.key, required this.task, required this.onDone});

  /// Durum eşikleri panodaki "yaklaşan bakım" ile aynıdır (14 gün).
  static Color statusColor(int daysRemaining) {
    if (daysRemaining < 0) return AppTheme.statusOverdue;
    if (daysRemaining <= 14) return AppTheme.statusUpcoming;
    return AppTheme.statusNormal;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final days = task.daysRemaining;
    final color = statusColor(days);
    final overdue = days < 0;

    final caption = overdue ? 'Gecikti' : (days == 0 ? 'Bugün' : 'Kalan gün');
    // Gecikmiş görevde halka tam dolu ve kırmızıdır.
    final progress = overdue ? 1.0 : (days / math.max(task.intervalDays, 1)).clamp(0.0, 1.0);

    return Semantics(
      label: '${task.name}, ${overdue ? '${-days} gün gecikti' : '$days gün kaldı'}',
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.30), color.withValues(alpha: 0.05)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(caption, style: theme.labelMedium?.copyWith(color: AppTheme.textSecondary)),
            const SizedBox(height: 10),
            SizedBox(
              width: 88,
              height: 88,
              child: CustomPaint(
                painter: _RingPainter(progress: progress, color: color),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${days.abs()}',
                        style: theme.headlineSmall?.copyWith(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.bold,
                          height: 1.1,
                        ),
                      ),
                      Text('Gün', style: theme.labelSmall?.copyWith(color: AppTheme.textSecondary)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              task.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.titleSmall?.copyWith(color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              '${task.intervalDays} günde bir',
              style: theme.bodySmall?.copyWith(color: AppTheme.textSecondary),
            ),
            const Spacer(),
            const SizedBox(height: 12),
            _DoneButton(onPressed: onDone),
          ],
        ),
      ),
    );
  }
}

class _DoneButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _DoneButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          gradient: AppTheme.accentGradient,
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPressed,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            child: const Text(
              'Yaptım',
              style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  static const _strokeWidth = 7.0;

  final double progress;
  final Color color;

  const _RingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(_strokeWidth / 2);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..color = Colors.white.withValues(alpha: 0.12);
    canvas.drawArc(arcRect, 0, math.pi * 2, false, track);

    if (progress <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = _strokeWidth
      ..color = color;
    canvas.drawArc(arcRect, -math.pi / 2, math.pi * 2 * progress, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.color != color;
}
