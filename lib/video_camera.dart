import 'video_camera_platform_interface.dart';

class VideoCamera {
  Future<String?> getPlatformVersion() {
    return VideoCameraPlatform.instance.getPlatformVersion();
  }

  Future<CameraInfo> checkCamera(CameraPosition position) {
    return VideoCameraPlatform.instance.checkCamera(position);
  }
}
