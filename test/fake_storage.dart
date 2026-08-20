import 'package:background_downloader/background_downloader.dart';

/// In-memory storage because real isolate storage bypasses mocked platform channels.
class MemoryStorage implements PersistentStorage {
  final _records = <String, TaskRecord>{};
  final _paused = <String, Task>{};
  final _resume = <String, ResumeData>{};

  @override
  (String, int) get currentDatabaseVersion => ('Memory', 1);

  @override
  Future<(String, int)> get storedDatabaseVersion async =>
      currentDatabaseVersion;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> storeTaskRecord(TaskRecord record) async =>
      _records[record.taskId] = record;

  @override
  Future<TaskRecord?> retrieveTaskRecord(String taskId) async =>
      _records[taskId];

  @override
  Future<List<TaskRecord>> retrieveAllTaskRecords() async =>
      _records.values.toList();

  @override
  Future<void> removeTaskRecord(String? taskId) async {
    taskId == null ? _records.clear() : _records.remove(taskId);
  }

  @override
  Future<void> storePausedTask(Task task) async => _paused[task.taskId] = task;

  @override
  Future<Task?> retrievePausedTask(String taskId) async => _paused[taskId];

  @override
  Future<List<Task>> retrieveAllPausedTasks() async => _paused.values.toList();

  @override
  Future<void> removePausedTask(String? taskId) async {
    taskId == null ? _paused.clear() : _paused.remove(taskId);
  }

  @override
  Future<void> storeResumeData(ResumeData resumeData) async =>
      _resume[resumeData.taskId] = resumeData;

  @override
  Future<ResumeData?> retrieveResumeData(String taskId) async =>
      _resume[taskId];

  @override
  Future<List<ResumeData>> retrieveAllResumeData() async =>
      _resume.values.toList();

  @override
  Future<void> removeResumeData(String? taskId) async {
    taskId == null ? _resume.clear() : _resume.remove(taskId);
  }
}
