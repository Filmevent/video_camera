import 'video_camera_platform_interface.dart';

export 'src/widgets/video_camera.dart';
export 'src/video_camera_controller.dart';

class VideoCamera {
  Future<String?> getPlatformVersion() {
    return VideoCameraPlatform.instance.getPlatformVersion();
  }
}
