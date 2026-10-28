enum MaintenanceOutcome {
  /// Cihazın birden fazla görevi var; hiçbir şey kaydedilmedi, kullanıcı seçecek.
  needsSelection,

  /// Bakım yeni kaydedildi.
  recorded,

  /// Aynı cihaz için kısa süre önce kayıt alınmıştı; yeni kayıt açılmadı.
  alreadyRecorded,

  /// Cihazda tanımlı bakım görevi yok.
  noTasks,
}

/// Kaydedilen tek bir görev; geri almak için gereken eski değeri taşır.
class RecordedTask {
  final int taskId;
  final String taskName;
  final int historyId;
  final DateTime? previousCompletedAt;
  final DateTime nextDueDate;

  const RecordedTask({
    required this.taskId,
    required this.taskName,
    required this.historyId,
    required this.previousCompletedAt,
    required this.nextDueDate,
  });
}

/// QR ile kaydedilen bakımın özeti. Başarı ekranı bunu gösterir, "Geri Al" bunu kullanır.
class MaintenanceReceipt {
  final int deviceId;
  final String deviceName;
  final MaintenanceOutcome outcome;
  final List<RecordedTask> recorded;
  final List<String> alreadyRecordedTaskNames;

  const MaintenanceReceipt({
    required this.deviceId,
    required this.deviceName,
    required this.outcome,
    this.recorded = const [],
    this.alreadyRecordedTaskNames = const [],
  });

  bool get canUndo => outcome == MaintenanceOutcome.recorded && recorded.isNotEmpty;

  List<String> get taskNames => outcome == MaintenanceOutcome.alreadyRecorded
      ? alreadyRecordedTaskNames
      : recorded.map((r) => r.taskName).toList();
}
