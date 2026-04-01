import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_download_manager_method_channel.dart';

abstract class FlutterDownloadManagerPlatform extends PlatformInterface {
  /// Constructs a FlutterDownloadManagerPlatform.
  FlutterDownloadManagerPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterDownloadManagerPlatform _instance = MethodChannelFlutterDownloadManager();

  /// The default instance of [FlutterDownloadManagerPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterDownloadManager].
  static FlutterDownloadManagerPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterDownloadManagerPlatform] when
  /// they register themselves.
  static set instance(FlutterDownloadManagerPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
