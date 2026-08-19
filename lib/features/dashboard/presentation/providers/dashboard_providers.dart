import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../data/local/isar_service.dart';
import '../../../../data/models/device_model.dart';

final isarServiceProvider = Provider<IsarService>((ref) {
  return IsarService();
});

final devicesProvider = StreamProvider<List<DeviceModel>>((ref) {
  final isarService = ref.watch(isarServiceProvider);
  return isarService.listenToDevices();
});

final deviceFilterProvider = StateProvider<String>((ref) => 'Tümü');
