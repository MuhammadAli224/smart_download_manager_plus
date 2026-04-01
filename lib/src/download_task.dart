import 'package:dio/dio.dart';

enum DownloadStatus { idle, downloading, paused, completed, error }
/// Represents a single download task.
///
/// Holds:
/// - URL
/// - progress
/// - status
/// - retry information
class DownloadTask {
  final String id;
  final String url;
  final String fileName;
  final String? subFolder;
  final Map<String, dynamic>? headers;
  final int maxRetries;
  final Duration retryDelay;
  final int priority; // higher = downloaded first

  double progress;
  DownloadStatus status;
  double speed; // bytes/sec
  int retryCount;
  String? savedPath; // real path after saveToDownloads

  CancelToken? cancelToken;

  int _lastReceivedBytes = 0;
  DateTime _lastSpeedCheck = DateTime.now();
  bool openAfterDownload;

  DownloadTask({
    required this.id,
    required this.url,
    required this.fileName,
    this.subFolder,
    this.headers,
    this.maxRetries = 0,
    this.retryDelay = const Duration(seconds: 2),
    this.priority = 0,
    this.progress = 0,
    this.status = DownloadStatus.idle,
    this.speed = 0,
    this.retryCount = 0,
    this.cancelToken,
    this.savedPath,
    this.openAfterDownload = false,
  });

  void updateSpeed(int receivedBytes) {
    final now = DateTime.now();
    final elapsed = now.difference(_lastSpeedCheck).inMilliseconds;
    if (elapsed >= 500) {
      final diff = receivedBytes - _lastReceivedBytes;
      speed = diff / (elapsed / 1000);
      _lastReceivedBytes = receivedBytes;
      _lastSpeedCheck = now;
    }
  }

  void resetSpeedTracking() {
    _lastReceivedBytes = 0;
    _lastSpeedCheck = DateTime.now();
    speed = 0;
  }

  /// Serialise to JSON for persistence
  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'fileName': fileName,
        'subFolder': subFolder,
        'headers': headers,
        'maxRetries': maxRetries,
        'retryDelay': retryDelay.inMilliseconds,
        'priority': priority,
        'progress': progress,
        'status': status.name,
        'retryCount': retryCount,
        'savedPath': savedPath,
        'openAfterDownload': openAfterDownload,
      };

  /// Deserialize from JSON for persistence
  factory DownloadTask.fromJson(Map<String, dynamic> json) => DownloadTask(
        id: json['id'],
        url: json['url'],
        fileName: json['fileName'],
        subFolder: json['subFolder'],
        headers: json['headers'] != null
            ? Map<String, dynamic>.from(json['headers'])
            : null,
        maxRetries: json['maxRetries'] ?? 0,
        retryDelay: Duration(milliseconds: json['retryDelay'] ?? 2000),
        priority: json['priority'] ?? 0,
        progress: (json['progress'] ?? 0).toDouble(),
        openAfterDownload: json['openAfterDownload'] ?? false,
        status: json['status'] == 'completed'
            ? DownloadStatus.completed
            : json['status'] == 'error'
                ? DownloadStatus.error
                : DownloadStatus.idle,
        retryCount: json['retryCount'] ?? 0,
        savedPath: json['savedPath'],
      );
}
