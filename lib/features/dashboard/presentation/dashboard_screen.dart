import 'package:flutter/material.dart';
import '../../../data/models/dummy_data.dart';
import '../../../core/theme/app_theme.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ev Sağlığı'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none),
            onPressed: () {},
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '19 Ağustos Çarşamba',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryCard(
                    context,
                    title: 'GECİKEN\nBAKIM',
                    count: '1',
                    subtitle: 'Daikin Klima\n18 gün gecikti',
                    color: AppTheme.statusOverdue.withOpacity(0.2),
                    textColor: AppTheme.statusOverdue,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildSummaryCard(
                    context,
                    title: 'YAKLAŞAN\nBAKIM',
                    count: '1',
                    subtitle: 'Roborock Q8\n12 gün sonra',
                    color: AppTheme.statusUpcoming.withOpacity(0.2),
                    textColor: AppTheme.statusUpcoming,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildWarrantyCard(context),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Tüm Cihazlar',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                TextButton(
                  onPressed: () {},
                  child: Text(
                    'Tümünü Gör',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                )
              ],
            ),
            const SizedBox(height: 16),
            ...DashboardDummyData.devices.map((d) => _buildDeviceRow(context, d)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        backgroundColor: AppTheme.primaryAction,
        child: const Icon(Icons.add, color: AppTheme.textPrimary),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildSummaryCard(
    BuildContext context, {
    required String title,
    required String count,
    required String subtitle,
    required Color color,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppTheme.textPrimary)),
          const SizedBox(height: 8),
          Text(count, style: Theme.of(context).textTheme.displayMedium),
          const SizedBox(height: 16),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: textColor)),
        ],
      ),
    );
  }

  Widget _buildWarrantyCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.infoWarranty.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('GARANTİ YAKLAŞIYOR', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppTheme.textPrimary)),
          const SizedBox(height: 8),
          Text('1', style: Theme.of(context).textTheme.displayMedium),
          const SizedBox(height: 16),
          Text('Samsung TV\n43 gün kaldı', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.infoWarranty)),
        ],
      ),
    );
  }

  Widget _buildDeviceRow(BuildContext context, DeviceDummy device) {
    return Container(
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
            ),
            child: const Icon(Icons.devices, color: AppTheme.textSecondary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.name, style: Theme.of(context).textTheme.titleMedium),
                Text(device.room, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Text(
            device.statusText,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: device.statusColor),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
        ],
      ),
    );
  }
}
