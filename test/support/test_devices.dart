import 'dart:collection';

import 'package:isar/isar.dart';

import 'package:homecare/data/models/device_model.dart';
import 'package:homecare/data/models/task_model.dart';

TaskModel taskOf(int id, String name, {required int intervalDays, required int completedDaysAgo}) {
  return TaskModel()
    ..id = id
    ..name = name
    ..intervalDays = intervalDays
    ..lastCompletedAt = DateTime.now().subtract(Duration(days: completedDaysAgo));
}

// ignore: subtype_of_sealed_class
/// Veritabanına bağlı olmayan `IsarLinks` öğeleri yineleyemez; testte görevleri bellekten verir.
class FakeLinks extends SetBase<TaskModel> implements IsarLinks<TaskModel> {
  final Set<TaskModel> _items;

  FakeLinks(Iterable<TaskModel> items) : _items = items.toSet();

  @override
  bool add(TaskModel value) => _items.add(value);

  @override
  bool contains(Object? element) => _items.contains(element);

  @override
  Iterator<TaskModel> get iterator => _items.iterator;

  @override
  int get length => _items.length;

  @override
  TaskModel? lookup(Object? element) => _items.lookup(element);

  @override
  bool remove(Object? value) => _items.remove(value);

  @override
  Set<TaskModel> toSet() => _items.toSet();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Görevleri bellekten dönen cihaz.
class TestDevice extends DeviceModel {
  final IsarLinks<TaskModel> _links;

  TestDevice(List<TaskModel> tasks) : _links = FakeLinks(tasks);

  @override
  IsarLinks<TaskModel> get tasks => _links;
}
