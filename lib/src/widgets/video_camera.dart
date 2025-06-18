import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:video_camera/src/video_camera_controller.dart';

class VideoCameraWidget extends StatefulWidget {
  const VideoCameraWidget({super.key, required this.controller});

  final VideoCameraController controller;

  @override
  State<VideoCameraWidget> createState() => _VideoCameraWidgetState();
}

class _VideoCameraWidgetState extends State<VideoCameraWidget> {
  @override
  Widget build(BuildContext context) {
    const String viewType = 'platform-view-type';

    return UiKitView(
      viewType: viewType,
      onPlatformViewCreated: _onPlatformViewCreated,
      layoutDirection: TextDirection.ltr,
      creationParams: const <String, dynamic>{},
      creationParamsCodec: const StandardMessageCodec(),
    );
  }

  void _onPlatformViewCreated(int id) {
    print("Initializing through the controller");
    widget.controller.initialize(id);
  }
}
