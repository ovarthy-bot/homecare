import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../dashboard/presentation/providers/dashboard_providers.dart';
import '../../../data/models/device_categories.dart';
import '../../../data/models/device_model.dart';

class DevicesScreen extends ConsumerStatefulWidget {
  const DevicesScreen({super.key});

  @override
  ConsumerState<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends ConsumerState<DevicesScreen> {
  String _searchQuery = '';
  String? _selectedCategory;

  final List<String> _filters = [
    'Tümü',
    'Bakım Gerekiyor',
    'Yaklaşan',
    'Garanti',
    'Sorunsuz',
  ];

  @override
  Widget build(BuildContext context) {
    final devicesAsyncValue = ref.watch(devicesProvider);
    final selectedFilter = ref.watch(deviceFilterProvider);

    // Yalnızca en az bir cihazın kullandığı kategoriler listelenir.
    final categories = (devicesAsyncValue.value ?? const <DeviceModel>[])
        .map((d) => d.category)
        .whereType<String>()
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final activeCategory = categories.contains(_selectedCategory) ? _selectedCategory : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cihazlar'),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(categories.isEmpty ? 110 : 158),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Cihaz ara...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 4.0,
                ),
                child: Row(
                  children: _filters.map((filter) {
                    final isSelected = selectedFilter == filter;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ChoiceChip(
                        label: Text(filter),
                        selected: isSelected,
                        onSelected: (selected) {
                          ref.read(deviceFilterProvider.notifier).state =
                              filter;
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
              if (categories.isNotEmpty)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 4.0,
                  ),
                  child: Row(
                    children: [
                      for (final category in [null, ...categories])
                        Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: ChoiceChip(
                            avatar: category == null
                                ? null
                                : Icon(DeviceCategories.iconFor(category), size: 18),
                            label: Text(category ?? 'Tüm Kategoriler'),
                            selected: activeCategory == category,
                            onSelected: (_) => setState(() => _selectedCategory = category),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      body: devicesAsyncValue.when(
        data: (devices) {
          final filteredDevices = devices.where((d) {
            if (_searchQuery.isNotEmpty &&
                !d.name.toLowerCase().contains(_searchQuery)) {
              return false;
            }
            if (activeCategory != null && d.category != activeCategory) {
              return false;
            }
            if (selectedFilter == 'Tümü') return true;

            int minDays = 9999;
            for (var t in d.tasks) {
              if (t.daysRemaining < minDays) minDays = t.daysRemaining;
            }

            if (selectedFilter == 'Bakım Gerekiyor') {
              return minDays < 0;
            }
            if (selectedFilter == 'Yaklaşan') {
              return minDays >= 0 && minDays <= 14;
            }
            if (selectedFilter == 'Garanti') {
              if (d.purchaseDate == null) return false;
              final expiry = d.purchaseDate!.add(
                Duration(days: 30 * d.warrantyMonths),
              );
              final daysLeft = expiry.difference(DateTime.now()).inDays;
              return daysLeft >= 0 && daysLeft <= 60;
            }
            if (selectedFilter == 'Sorunsuz') {
              bool isWarrantyOk = true;
              if (d.purchaseDate != null) {
                final expiry = d.purchaseDate!.add(
                  Duration(days: 30 * d.warrantyMonths),
                );
                final daysLeft = expiry.difference(DateTime.now()).inDays;
                if (daysLeft < 0 || daysLeft <= 60) isWarrantyOk = false;
              }
              return minDays > 14 && isWarrantyOk;
            }
            return true;
          }).toList();

          if (filteredDevices.isEmpty) {
            return const Center(
              child: Text('Kriterlere uygun cihaz bulunamadı.'),
            );
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
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(DeviceCategories.iconFor(device.category), color: Colors.grey),
                        ),
                  title: Text(device.name),
                  subtitle: Text(
                    device.category == null || device.category!.isEmpty
                        ? device.room
                        : '${device.room} · ${device.category}',
                  ),
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
