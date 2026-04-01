import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_download_manager_platform_interface.dart';

/// An implementation of [FlutterDownloadManagerPlatform] that uses method channels.
class MethodChannelFlutterDownloadManager extends FlutterDownloadManagerPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_download_manager');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
