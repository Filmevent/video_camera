import 'package:flutter_test/flutter_test.dart';
import 'package:video_camera/video_camera.dart';
import 'package:video_camera/video_camera_platform_interface.dart';
import 'package:video_camera/video_camera_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockVideoCameraPlatform
    with MockPlatformInterfaceMixin
    implements VideoCameraPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final VideoCameraPlatform initialPlatform = VideoCameraPlatform.instance;

  test('$MethodChannelVideoCamera is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelVideoCamera>());
  });

  test('getPlatformVersion', () async {
    VideoCamera videoCameraPlugin = VideoCamera();
    MockVideoCameraPlatform fakePlatform = MockVideoCameraPlatform();
    VideoCameraPlatform.instance = fakePlatform;

    expect(await videoCameraPlugin.getPlatformVersion(), '42');
  });
}
