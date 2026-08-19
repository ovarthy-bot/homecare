import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../dashboard/presentation/providers/dashboard_providers.dart';
import '../../../data/models/device_model.dart';

class DevicesScreen extends ConsumerStatefulWidget {
  const DevicesScreen({super.key});

  @override
  ConsumerState<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends ConsumerState<DevicesScreen> {
  String _searchQuery = '';

  final List<String> _filters = [
    'Tümü',
    'Bakım Gerekiyor',
    'Yaklaşan',
    'Garanti',
    'Sorunsuz'
  ];

  @override
  Widget build(BuildContext context) {
    final devicesAsyncValue = ref.watch(devicesProvider);
    final _selectedFilter = ref.watch(deviceFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cihazlar'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(110),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Cihaz ara...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val.toLowerCase();
                    });
                  },
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                child: Row(
                  children: _filters.map((filter) {
                    final isSelected = _selectedFilter == filter;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ChoiceChip(
                        label: Text(filter),
                        selected: isSelected,
                        onSelected: (selected) {
                          ref.read(deviceFilterProvider.notifier).state = filter;
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
      body: devicesAsyncValue.when(
        data: (devices) {
          final filteredDevices = devices.where((d) {
            if (_searchQuery.isNotEmpty && !d.name.toLowerCase().contains(_searchQuery)) {
              return false;
            }
            if (_selectedFilter == 'Tümü') return true;
            
            int minDays = 9999;
            for (var t in d.tasks) {
              if (t.daysRemaining < minDays) minDays = t.daysRemaining;
            }

            if (_selectedFilter == 'Bakım Gerekiyor') {
              return minDays < 0;
            }
            if (_selectedFilter == 'Yaklaşan') {
              return minDays >= 0 && minDays <= 14;
            }
            if (_selectedFilter == 'Garanti') {
              if (d.purchaseDate == null) return false;
              final expiry = d.purchaseDate!.add(Duration(days: 30 * d.warrantyMonths));
              final daysLeft = expiry.difference(DateTime.now()).inDays;
              return daysLeft >= 0 && daysLeft <= 60;
            }
            if (_selectedFilter == 'Sorunsuz') {
              bool isWarrantyOk = true;
              if (d.purchaseDate != null) {
                final expiry = d.purchaseDate!.add(Duration(days: 30 * d.warrantyMonths));
                final daysLeft = expiry.difference(DateTime.now()).inDays;
                if (daysLeft < 0 || daysLeft <= 60) isWarrantyOk = false;
              }
              return minDays > 14 && isWarrantyOk;
            }
            return true;
          }).toList();

          if (filteredDevices.isEmpty) {
            return const Center(child: Text('Kriterlere uygun cihaz bulunamadı.'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: filteredDevices.length,
            itemBuilder: (context, index) {
              final device = filteredDevices[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: device.imagePath != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(device.imagePath!),
                            width: 50,
                            height: 50,
                            fit: BoxFit.cover,
                          ),
                        )
                      : Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.devices, color: Colors.grey),
                        ),
                  title: Text(device.name),
                  subtitle: Text(device.room),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    context.push('/device/${device.id}');
                  },
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Hata: $e')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          context.push('/devices/add');
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
