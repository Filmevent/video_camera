import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'video_camera_platform_interface.dart';

/// An implementation of [VideoCameraPlatform] that uses method channels.
class MethodChannelVideoCamera extends VideoCameraPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('video_camera');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
