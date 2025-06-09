import 'package:flutter_test/flutter_test.dart';
import 'package:video_camera/video_camera.dart';
import 'package:video_camera/video_camera_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// Create a mock implementation for testing
class MockVideoCameraPlatform
    with MockPlatformInterfaceMixin
    implements VideoCameraPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Future<CameraInfo> checkCamera(CameraPosition position) => Future.value(
    CameraInfo(
      isAvailable: true,
      hasPermission: position == CameraPosition.front,
      errorMessage: position == CameraPosition.back ? 'Test error' : null,
    ),
  );
}

void main() {
  group('VideoCamera', () {
    late VideoCamera videoCameraPlugin;
    late MockVideoCameraPlatform fakePlatform;

    setUp(() {
      videoCameraPlugin = VideoCamera();
      fakePlatform = MockVideoCameraPlatform();
      VideoCameraPlatform.instance = fakePlatform;
    });

    test('getPlatformVersion', () async {
      expect(await videoCameraPlugin.getPlatformVersion(), '42');
    });

    test('checkCamera - front camera', () async {
      final info = await videoCameraPlugin.checkCamera(CameraPosition.front);

      expect(info.isAvailable, true);
      expect(info.hasPermission, true);
      expect(info.errorMessage, isNull);
    });

    test('checkCamera - back camera', () async {
      final info = await videoCameraPlugin.checkCamera(CameraPosition.back);

      expect(info.isAvailable, true);
      expect(info.hasPermission, false);
      expect(info.errorMessage, 'Test error');
    });
  });
}
