import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'video_camera_method_channel.dart';
import 'src/generated/camera_api.g.dart';

export 'src/generated/camera_api.g.dart' show CameraPosition, CameraInfo;

abstract class VideoCameraPlatform extends PlatformInterface {
  /// Constructs a VideoCameraPlatform.
  VideoCameraPlatform() : super(token: _token);

  static final Object _token = Object();

  static VideoCameraPlatform _instance = MethodChannelVideoCamera();

  /// The default instance of [VideoCameraPlatform] to use.
  ///
  /// Defaults to [MethodChannelVideoCamera].
  static VideoCameraPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [VideoCameraPlatform] when
  /// they register themselves.
  static set instance(VideoCameraPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<CameraInfo> checkCamera(CameraPosition position) {
    throw UnimplementedError('checkCamera() has not been implemented.');
  }
}
