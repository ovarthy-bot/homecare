import 'package:flutter/material.dart';

class DeviceDummy {
  final String id;
  final String name;
  final String room;
  final String statusText;
  final Color statusColor;

  DeviceDummy({
    required this.id,
    required this.name,
    required this.room,
    required this.statusText,
    required this.statusColor,
  });
}

class DashboardDummyData {
  static final List<DeviceDummy> devices = [
    DeviceDummy(
      id: '1',
      name: 'Daikin Klima',
      room: 'Salon',
      statusText: '18 gün gecikti',
      statusColor: const Color(0xFFF44336), // Red
    ),
    DeviceDummy(
      id: '2',
      name: 'Roborock Q8',
      room: 'Salon',
      statusText: '12 gün sonra',
      statusColor: const Color(0xFFFFB300), // Amber
    ),
    DeviceDummy(
      id: '3',
      name: 'Samsung TV',
      room: 'Oturma Odası',
      statusText: '43 gün kaldı',
      statusColor: const Color(0xFF29B6F6), // Cyan
    ),
    DeviceDummy(
      id: '4',
      name: 'Kahve Makinesi',
      room: 'Mutfak',
      statusText: 'Her şey yolunda',
      statusColor: const Color(0xFF4CAF50), // Green
    ),
  ];
}
