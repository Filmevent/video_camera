import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:video_camera/src/generated/camera_api.g.dart';

import 'video_camera_platform_interface.dart';

/// An implementation of [VideoCameraPlatform] that uses method channels.
class MethodChannelVideoCamera extends VideoCameraPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('video_camera');

  late final CameraHostApi _cameraApi = CameraHostApi();

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }

  @override
  Future<CameraInfo> checkCamera(CameraPosition position) async {
    return await _cameraApi.checkCamera(position);
  }
}
