import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../smart_download_manager_plus.dart';

/// A powerful controller for managing file downloads in Flutter.
///
/// This controller provides a full-featured download system including:
///
/// - 📥 Multiple concurrent downloads
/// - ⏸ Pause & ▶ Resume support
/// - 🔁 Automatic retry mechanism
/// - 📊 Progress & speed tracking
/// - 🔔 Native notifications (Android)
/// - 💾 Persistent storage of tasks
/// - 📂 Save files to Downloads (Android) or Documents (iOS)
/// - 🚀 Priority-based queue system
///
/// ## Example
///
/// ```dart
/// final controller = DownloadController(
///   maxConcurrent: 2,
///   onTaskCompleted: (task) {
///     print('Download completed: ${task.fileName}');
///   },
/// );
///
/// final task = controller.addTask(
///   'https://example.com/file.pdf',
///   openAfterDownload: true,
/// );
///
/// controller.startTask(task);
/// ```
///
/// ## Notes
///
/// - On Android, files are saved to the **Downloads** folder.
/// - On iOS, files are saved to the **Application Documents directory**.
/// - Supports resuming downloads if partial files exist.
///
/// See also:
/// - [DownloadTask]
/// - [DownloadStatus]
class DownloadController {
  /// Maximum number of concurrent downloads.
  final int maxConcurrent;
  final void Function(DownloadTask task)? onTaskProgress;
  final void Function(DownloadTask task)? onTaskCompleted;
  final void Function(DownloadTask task)? onTaskFailed;
  final void Function(DownloadTask task)? onTaskPaused;

  final Dio _dio = Dio();
  static const MethodChannel _channel = MethodChannel('download_channel');
  static const String _prefsKey = 'fdm_tasks';

  final List<DownloadTask> tasks = [];
  final _streamController = StreamController<DownloadTask>.broadcast();

  Stream<DownloadTask> get onTaskUpdated => _streamController.stream;

  int get _activeCount =>
      tasks.where((t) => t.status == DownloadStatus.downloading).length;

  /// Creates a [DownloadController].
  ///
  /// The [maxConcurrent] parameter limits how many downloads can run at once.
  /// If set to `0`, there is no limit.
  ///
  /// Callback parameters:
  /// - [onTaskProgress]: Called when progress updates.
  /// - [onTaskCompleted]: Called when a task completes successfully.
  /// - [onTaskFailed]: Called when a task fails.
  /// - [onTaskPaused]: Called when a task is paused.
  DownloadController({
    this.maxConcurrent = 0,
    this.onTaskProgress,
    this.onTaskCompleted,
    this.onTaskFailed,
    this.onTaskPaused,
  });

  // ── Logging ────────────────────────────────────────────────────────────────

  static void _log(String message, {String? tag, Object? error}) {
    dev.log(
      message,
      name: 'DownloadController${tag != null ? '/$tag' : ''}',
      error: error,
      time: DateTime.now(),
    );
  }

  // ── Persistence ────────────────────────────────────────────────────────────

  Future<void> _saveTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = tasks.map((t) => jsonEncode(t.toJson())).toList();
      await prefs.setStringList(_prefsKey, json);
      _log('Tasks persisted → count=${tasks.length}', tag: 'persist');
    } catch (e) {
      _log('Failed to persist tasks → $e', tag: 'persist', error: e);
    }
  }

  /// Restores previously saved tasks from local storage.
  ///
  /// Uses [SharedPreferences] internally.
  Future<void> restoreTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_prefsKey) ?? [];
      tasks.clear();
      for (final s in raw) {
        tasks.add(DownloadTask.fromJson(jsonDecode(s)));
      }
      _log('Tasks restored → count=${tasks.length}', tag: 'persist');
    } catch (e) {
      _log('Failed to restore tasks → $e', tag: 'persist', error: e);
    }
  }

  /// 🔹 addTask
  /// Adds a new download task to the queue.
  ///
  /// Parameters:
  /// - [url]: The file URL to download.
  /// - [fileName]: Optional custom file name. Defaults to URL last segment.
  /// - [subFolder]: Optional subfolder inside Downloads (Android only).
  /// - [headers]: Optional HTTP headers.
  /// - [maxRetries]: Number of retry attempts on failure.
  /// - [retryDelay]: Delay between retries.
  /// - [priority]: Higher values are downloaded first.
  /// - [openAfterDownload]: Automatically open file after completion.
  ///
  /// Returns the created [DownloadTask].
  ///
  /// Example:
  /// ```dart
  /// controller.addTask(
  ///   'https://example.com/image.png',
  ///   priority: 10,
  /// );
  /// ```
  DownloadTask addTask(
    String url, {
    String? fileName,
    String? subFolder,
    Map<String, dynamic>? headers,
    int maxRetries = 0,
    Duration retryDelay = const Duration(seconds: 2),
    int priority = 0,
    bool openAfterDownload = false,
  }) {
    final resolvedName = fileName ?? Uri.parse(url).pathSegments.last;

    _log(
      'addTask → url=$url, fileName=$resolvedName, '
      'subFolder=$subFolder, priority=$priority, '
      'maxRetries=$maxRetries, headers=${headers?.keys}',
      tag: 'addTask',
    );

    final task = DownloadTask(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      url: url,
      fileName: resolvedName,
      subFolder: subFolder,
      headers: headers,
      maxRetries: maxRetries,
      retryDelay: retryDelay,
      priority: priority,
      openAfterDownload: openAfterDownload,
    );

    tasks.add(task);
    _sortByPriority();
    _saveTasks();

    _log('Task created → id=${task.id}, fileName=${task.fileName}',
        tag: 'addTask');
    return task;
  }

  /// Adds multiple download tasks at once.
  ///
  /// All tasks share the same configuration.
  ///
  /// Example:
  /// ```dart
  /// controller.addBatch([
  ///   'https://example.com/file1.pdf',
  ///   'https://example.com/file2.pdf',
  /// ]);
  /// ```
  List<DownloadTask> addBatch(
    List<String> urls, {
    String? subFolder,
    Map<String, dynamic>? headers,
    int maxRetries = 0,
    Duration retryDelay = const Duration(seconds: 2),
    int priority = 0,
  }) {
    _log('addBatch → count=${urls.length}', tag: 'addBatch');

    final created = urls
        .map((url) => addTask(
              url,
              subFolder: subFolder,
              headers: headers,
              maxRetries: maxRetries,
              retryDelay: retryDelay,
              priority: priority,
            ))
        .toList();

    _log(
      'Batch created → ids=${created.map((t) => t.id).join(', ')}',
      tag: 'addBatch',
    );

    return created;
  }

  /// Starts all pending (idle or paused) tasks.
  ///
  /// Respects the [maxConcurrent] limit.
  Future<void> startTask(
    DownloadTask task, {
    Function()? onUpdate,
    bool showNotification = true,
  }) async {
    _log(
      'startTask → id=${task.id}, fileName=${task.fileName}, '
      'openAfterDownload=${task.openAfterDownload}, showNotification=$showNotification',
      tag: 'startTask',
    );
    final shouldOpen = task.openAfterDownload;
    if (task.status == DownloadStatus.downloading) {
      _log('Skipped — already downloading id=${task.id}', tag: 'startTask');
      return;
    }

    if (maxConcurrent > 0 && _activeCount >= maxConcurrent) {
      _log(
        'Concurrent limit reached ($maxConcurrent) → queuing id=${task.id}',
        tag: 'startTask',
      );
      task.status = DownloadStatus.idle;
      _notify(task, onUpdate);
      return;
    }

    final tempDir = await getTemporaryDirectory();
    final tempPath = '${tempDir.path}/${task.id}_${task.fileName}';
    _log('Temp path → $tempPath', tag: 'startTask');

    final cancelToken = CancelToken();
    task.cancelToken = cancelToken;
    task.resetSpeedTracking();
    task.status = DownloadStatus.downloading;
    _notify(task, onUpdate);

    final notifId = int.parse(task.id) % 100000;
    _log('Notification ID → $notifId', tag: 'startTask');

    if (showNotification) {
      await DownloadNotificationService.showProgress(
        id: notifId,
        title: task.fileName,
        progress: 0,
      );
      _log('Initial progress notification shown', tag: 'startTask');
    }

    // ── Resume: check if partial temp file exists ──────────────────────────
    int startByte = 0;
    final tempFile = File(tempPath);
    if (await tempFile.exists()) {
      startByte = await tempFile.length();
      _log(
        'Partial file found → resuming from byte $startByte '
        '(${_fmt(startByte)} already downloaded)',
        tag: 'startTask',
      );
    } else {
      _log('No partial file → starting fresh', tag: 'startTask');
    }

    // Merge user headers with Range header for resume
    final mergedHeaders = {
      ...?task.headers,
      if (startByte > 0) 'Range': 'bytes=$startByte-',
    };

    _log(
      'Request headers → $mergedHeaders',
      tag: 'startTask',
    );

    String? savedPath;
    bool wasPaused = false;

    try {
      _log('Starting Dio download → ${task.url}', tag: 'startTask');

      await _dio.downloadUri(
        Uri.parse(task.url),
        tempPath,
        cancelToken: cancelToken,
        deleteOnError: false, // keep partial file so we can resume later
        options: Options(
          headers: mergedHeaders,
          // // appendMode allows writing from where we left off
          // responseType: ResponseType.stream,
          followRedirects: true,
        ),
        onReceiveProgress: (received, total) {
          // `received` is bytes received in THIS session
          // `total` may be -1 if server doesn't send Content-Length
          final totalReceived = startByte + received;
          final grandTotal = total == -1 ? -1 : startByte + total;

          if (grandTotal != -1) {
            task.progress = totalReceived / grandTotal;
          }
          task.updateSpeed(totalReceived);
          _notify(task, onUpdate);

          final percent = grandTotal != -1 ? (task.progress * 100).toInt() : -1;

          _log(
            'Progress → ${percent == -1 ? '?' : '$percent'}% | '
            'session=${_fmt(received)} | '
            'total=${_fmt(totalReceived)} | '
            'speed=${task.speed.toStringAsFixed(0)} B/s',
            tag: 'progress',
          );

          if (showNotification && percent != -1) {
            DownloadNotificationService.showProgress(
              id: notifId,
              title: task.fileName,
              progress: percent,
            );
          }
        },
      );

      _log('Dio download finished → saving to Downloads', tag: 'startTask');

      if (Platform.isAndroid) {
        _log(
          'Invoking saveToDownloads → '
          'filePath=$tempPath, '
          'fileName=${task.fileName}, '
          'subFolder=${task.subFolder}',
          tag: 'startTask',
        );

        savedPath = await _channel.invokeMethod<String>(
          'saveToDownloads',
          {
            'filePath': tempPath,
            'fileName': task.fileName,
            if (task.subFolder != null) 'subFolder': task.subFolder,
          },
        );

        _log('saveToDownloads succeeded → savedPath=$savedPath',
            tag: 'startTask');
        task.savedPath = savedPath;
      }
      if (Platform.isIOS) {
        final dir = await getApplicationDocumentsDirectory();
        final newPath = '${dir.path}/${task.fileName}';
        await File(tempPath).copy(newPath);
        task.savedPath = newPath;
      }

      task.status = DownloadStatus.completed;
      task.progress = 1.0;
      task.retryCount = 0;
      _notify(task, onUpdate);
      onTaskCompleted?.call(task);
      _log('Task completed → id=${task.id}', tag: 'startTask');
      await _saveTasks();

      if (showNotification) {
        await DownloadNotificationService.complete(
          id: notifId,
          title: task.fileName,
        );
        _log('Completion notification shown', tag: 'startTask');
      }

      if (shouldOpen) {
        final pathToOpen =
            Platform.isAndroid ? (savedPath ?? tempPath) : tempPath;

        _log('Opening file → $pathToOpen', tag: 'startTask');

        final openResult = await OpenFilex.open(
          pathToOpen,
          type: FileHelper.getMimeType(task.fileName),
        );

        _log(
          'OpenFilex result → '
          'type=${openResult.type.name}, '
          'message=${openResult.message}',
          tag: 'startTask',
        );
      }

      _startNextQueued(onUpdate: onUpdate, showNotification: showNotification);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        wasPaused = true;
        _log(
          'Download paused → id=${task.id}, reason=${e.message}',
          tag: 'startTask',
        );
        task.status = DownloadStatus.paused;
        onTaskPaused?.call(task);

        if (showNotification) {
          await DownloadNotificationService.cancel(notifId);
        }
      } else {
        _log(
          'Dio error → ${e.type.name}: ${e.message}',
          tag: 'startTask',
          error: e,
        );

        final shouldRetry = task.retryCount < task.maxRetries;
        _log(
          'Retry check → retryCount=${task.retryCount}, '
          'maxRetries=${task.maxRetries}, shouldRetry=$shouldRetry',
          tag: 'startTask',
        );

        if (shouldRetry) {
          task.retryCount++;
          task.status = DownloadStatus.idle;
          _notify(task, onUpdate);
          _log(
            'Retrying in ${task.retryDelay.inSeconds}s → '
            'attempt=${task.retryCount}/${task.maxRetries}',
            tag: 'startTask',
          );
          await Future.delayed(task.retryDelay);
          await startTask(
            task,
            onUpdate: onUpdate,
            showNotification: showNotification,
          );
          return;
        }

        task.status = DownloadStatus.error;
        onTaskFailed?.call(task);

        if (showNotification) {
          await DownloadNotificationService.showError(
            id: notifId,
            title: task.fileName,
          );
        }
      }
    } catch (e) {
      _log('Unexpected error → $e', tag: 'startTask', error: e);
      task.status = DownloadStatus.error;
      onTaskFailed?.call(task);

      if (showNotification) {
        await DownloadNotificationService.showError(
          id: notifId,
          title: task.fileName,
        );
      }
    } finally {
      final shouldDelete = !wasPaused &&
          (task.status == DownloadStatus.completed ||
              task.status == DownloadStatus.error);

      _log(
        'finally → wasPaused=$wasPaused, '
        'status=${task.status.name}, '
        'shouldDelete=$shouldDelete',
        tag: 'startTask',
      );

      if (shouldDelete) {
        try {
          final f = File(tempPath);
          if (await f.exists()) {
            await f.delete();
            _log('Temp file deleted → $tempPath', tag: 'startTask');
          } else {
            _log('Temp file already gone → $tempPath', tag: 'startTask');
          }
        } catch (deleteErr) {
          // Log but never throw — a cleanup failure should not crash the app
          _log(
            'Failed to delete temp file → $deleteErr',
            tag: 'startTask',
            error: deleteErr,
          );
        }
      } else {
        _log(
          'Temp file kept for resume → $tempPath '
          '(${_fmt(await File(tempPath).exists() ? await File(tempPath).length() : 0)} on disk)',
          tag: 'startTask',
        );
      }
    }

    _log(
      'Final status → id=${task.id}, status=${task.status.name}',
      tag: 'startTask',
    );
    _notify(task, onUpdate);
    await _saveTasks();
  }

  // ── Batch controls ─────────────────────────────────────────────────────────

  Future<void> startAll({
    Function()? onUpdate,
    bool showNotification = true,
  }) async {
    _log('startAll → idle/paused count='
        '${tasks.where((t) => t.status == DownloadStatus.idle || t.status == DownloadStatus.paused).length}');

    final toStart = tasks
        .where((t) =>
            t.status == DownloadStatus.idle ||
            t.status == DownloadStatus.paused)
        .toList();

    for (final task in toStart) {
      await startTask(task,
          onUpdate: onUpdate, showNotification: showNotification);
    }
  }

  void pauseAll({Function()? onUpdate}) {
    _log('pauseAll → active count=$_activeCount');
    for (final task in tasks) {
      if (task.status == DownloadStatus.downloading) {
        pauseTask(task, onUpdate: onUpdate);
      }
    }
  }

  Future<void> cancelAll({Function()? onUpdate}) async {
    _log('cancelAll → task count=${tasks.length}');
    for (final task in [...tasks]) {
      await cancelTask(task, onUpdate: onUpdate);
    }
  }

  // ── Individual controls ────────────────────────────────────────────────────
  /// Pauses an active download task.
  ///
  /// The download can later be resumed using [resumeTask].
  void pauseTask(DownloadTask task, {Function()? onUpdate}) {
    _log('pauseTask → id=${task.id}, fileName=${task.fileName}',
        tag: 'pauseTask');
    task.cancelToken?.cancel('User paused');
    task.status = DownloadStatus.paused;
    onTaskPaused?.call(task);
    _notify(task, onUpdate);
    _log('Task paused → id=${task.id}', tag: 'pauseTask');
  }

  /// Resumes a paused download task.
  ///
  /// This internally calls [startTask] and continues
  /// from the last downloaded byte.
  Future<void> resumeTask(
    DownloadTask task, {
    Function()? onUpdate,
    bool showNotification = true,
  }) async {
    _log(
      'resumeTask → id=${task.id}, '
      'progress=${(task.progress * 100).toStringAsFixed(1)}%',
      tag: 'resumeTask',
    );
    await startTask(task,
        onUpdate: onUpdate, showNotification: showNotification);
  }

  /// Cancels a download task completely.
  ///
  /// This will:
  /// - Stop the download
  /// - Delete any partial file
  /// - Reset progress
  Future<void> cancelTask(DownloadTask task, {Function()? onUpdate}) async {
    _log('cancelTask → id=${task.id}, fileName=${task.fileName}',
        tag: 'cancelTask');

    task.cancelToken?.cancel('User cancelled');
    task.status = DownloadStatus.idle;
    task.progress = 0;
    task.retryCount = 0;

    // Delete partial temp file on explicit cancel (user doesn't want to resume)
    final tempDir = await getTemporaryDirectory();
    final tempPath = '${tempDir.path}/${task.id}_${task.fileName}';
    try {
      final f = File(tempPath);
      if (await f.exists()) {
        await f.delete();
        _log('Partial temp file deleted on cancel → $tempPath',
            tag: 'cancelTask');
      }
    } catch (e) {
      _log('Could not delete temp on cancel → $e', tag: 'cancelTask');
    }

    final notifId = int.parse(task.id) % 100000;
    await DownloadNotificationService.cancel(notifId);
    _log('Notification cancelled → notifId=$notifId', tag: 'cancelTask');

    _notify(task, onUpdate);
    await _saveTasks();
    _log('Task reset to idle → id=${task.id}', tag: 'cancelTask');
  }

  /// Removes a task from the controller.
  ///
  /// This also cancels the task if it is active.
  void removeTask(DownloadTask task, {Function()? onUpdate}) {
    _log('removeTask → id=${task.id}, fileName=${task.fileName}',
        tag: 'removeTask');
    cancelTask(task);
    tasks.remove(task);
    _saveTasks();
    onUpdate?.call();
    _log('Task removed → remaining=${tasks.length}', tag: 'removeTask');
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _notify(DownloadTask task, Function()? onUpdate) {
    _streamController.add(task);
    onTaskProgress?.call(task);
    onUpdate?.call();
  }

  void _sortByPriority() {
    tasks.sort((a, b) => b.priority.compareTo(a.priority));
  }

  void _startNextQueued({Function()? onUpdate, bool showNotification = true}) {
    if (maxConcurrent <= 0) return;
    if (_activeCount >= maxConcurrent) return;

    final candidates = tasks.where(
      (t) =>
          t.status == DownloadStatus.idle || t.status == DownloadStatus.paused,
    );
    if (candidates.isEmpty) return;

    final next = candidates.first;
    _log('Auto-starting next queued → id=${next.id}', tag: 'queue');
    startTask(next, onUpdate: onUpdate, showNotification: showNotification);
  }

  String _fmt(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)}MB';
  }

  /// Disposes the controller and closes internal streams.
  ///
  /// Must be called to avoid memory leaks.
  void dispose() {
    _streamController.close();
    _log('DownloadController disposed');
  }
}
