import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/dashboard_providers.dart';
import '../../../data/models/device_model.dart';
import '../../../core/theme/app_theme.dart';
import 'package:go_router/go_router.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devicesAsyncValue = ref.watch(devicesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ev Sağlığı'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () {
              context.push('/scanner');
            },
          ),
          IconButton(
            icon: const Icon(Icons.notifications_none),
            onPressed: () {},
          ),
        ],
      ),
      body: devicesAsyncValue.when(
        data: (devices) {
          int overdueCount = 0;
          int upcomingCount = 0;
          DeviceModel? mostOverdueDevice;
          DeviceModel? upcomingDevice;

          for (var device in devices) {
            for (var task in device.tasks) {
              final days = task.daysRemaining;
              if (days < 0) {
                overdueCount++;
                mostOverdueDevice ??= device;
              } else if (days <= 14) {
                upcomingCount++;
                upcomingDevice ??= device;
              }
            }
          }

          int totalWarrantyExpiring = 0;
          DeviceModel? closestWarrantyDevice;
          for (var device in devices) {
            if (device.purchaseDate != null) {
              final expiry = device.purchaseDate!.add(Duration(days: 30 * device.warrantyMonths));
              final daysLeft = expiry.difference(DateTime.now()).inDays;
              if (daysLeft >= 0 && daysLeft <= 60) {
                totalWarrantyExpiring++;
                if (closestWarrantyDevice == null || 
                    closestWarrantyDevice.purchaseDate!.add(Duration(days: 30 * closestWarrantyDevice.warrantyMonths)).difference(DateTime.now()).inDays > daysLeft) {
                  closestWarrantyDevice = device;
                }
              }
            }
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Özet', // Date can be dynamic later
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: _buildSummaryCard(
                        context,
                        ref,
                        title: 'GECİKEN\nBAKIM',
                        count: overdueCount.toString(),
                        subtitle: mostOverdueDevice != null
                            ? mostOverdueDevice.name
                            : 'Gecikme yok',
                        color: AppTheme.statusOverdue.withValues(alpha: 0.2),
                        textColor: AppTheme.statusOverdue,
                        filterTarget: 'Bakım Gerekiyor',
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildSummaryCard(
                        context,
                        ref,
                        title: 'YAKLAŞAN\nBAKIM',
                        count: upcomingCount.toString(),
                        subtitle: upcomingDevice != null
                            ? upcomingDevice.name
                            : 'Yaklaşan yok',
                        color: AppTheme.statusUpcoming.withValues(alpha: 0.2),
                        textColor: AppTheme.statusUpcoming,
                        filterTarget: 'Yaklaşan',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildWarrantyCard(context, ref, totalWarrantyExpiring, closestWarrantyDevice),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Tüm Cihazlar',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    TextButton(
                      onPressed: () {
                        context.go('/devices');
                      },
                      child: Text(
                        'Tümünü Gör',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ...devices.map((d) => _buildDeviceRow(context, d)),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Hata: $e')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          context.push('/devices/add');
        },
        backgroundColor: AppTheme.primaryAction,
        child: const Icon(Icons.add, color: AppTheme.textPrimary),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildSummaryCard(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String count,
    required String subtitle,
    required Color color,
    required Color textColor,
    required String filterTarget,
  }) {
    return GestureDetector(
      onTap: () {
        ref.read(deviceFilterProvider.notifier).state = filterTarget;
        context.go('/devices');
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(count, style: Theme.of(context).textTheme.displayMedium),
            const SizedBox(height: 16),
            Text(
              subtitle,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: textColor),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWarrantyCard(BuildContext context, WidgetRef ref, int count, DeviceModel? closestDevice) {
    return GestureDetector(
      onTap: () {
        ref.read(deviceFilterProvider.notifier).state = 'Garanti';
        context.go('/devices');
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.infoWarranty.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'GARANTİ YAKLAŞIYOR',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(count.toString(), style: Theme.of(context).textTheme.displayMedium),
            const SizedBox(height: 16),
            Text(
              closestDevice != null ? '${closestDevice.name} (Yaklaşıyor)' : 'Kayıtlı garanti yok / Süresi dolmuş',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppTheme.infoWarranty),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceRow(BuildContext context, DeviceModel device) {
    String statusText = 'Her şey yolunda';
    Color statusColor = AppTheme.statusNormal;

    if (device.tasks.isNotEmpty) {
      var urgentTask = device.tasks.first;
      for (var task in device.tasks) {
        if (task.daysRemaining < urgentTask.daysRemaining) {
          urgentTask = task;
        }
      }

      final days = urgentTask.daysRemaining;
      if (days < 0) {
        statusText = '${-days} gün gecikti';
        statusColor = AppTheme.statusOverdue;
      } else if (days <= 14) {
        statusText = '$days gün sonra';
        statusColor = AppTheme.statusUpcoming;
      } else {
        statusText = 'Durum iyi';
        statusColor = AppTheme.statusNormal;
      }
    }

    return GestureDetector(
      onTap: () {
        context.push('/device/${device.id}');
      },
      child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
              image: device.imagePath != null ? DecorationImage(
                image: FileImage(File(device.imagePath!)),
                fit: BoxFit.cover,
              ) : null,
            ),
            child: device.imagePath == null 
              ? const Icon(Icons.devices, color: AppTheme.textSecondary)
              : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(device.room, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Text(
            statusText,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: statusColor),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
        ],
      ),
    ),
    );
  }
}
