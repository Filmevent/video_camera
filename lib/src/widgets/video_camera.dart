import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:video_camera/src/video_camera_controller.dart';
import 'package:video_camera/src/widgets/lut_carousel.dart';

class VideoCameraWidget extends StatefulWidget {
  const VideoCameraWidget({super.key, required this.controller});
  final VideoCameraController controller;

  @override
  State<VideoCameraWidget> createState() => _VideoCameraWidgetState();
}

class _VideoCameraWidgetState extends State<VideoCameraWidget>
    with WidgetsBindingObserver {
  static const _viewType = 'platform-view-type';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        widget.controller.pauseCamera();
        break;
      case AppLifecycleState.resumed:
        widget.controller.resumeCamera();
        break;
      case AppLifecycleState.detached:
        widget.controller.dispose();
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        UiKitView(
          viewType: _viewType,
          onPlatformViewCreated: (id) => widget.controller.initialize(id),
          layoutDirection: TextDirection.ltr,
          creationParams: const {},
          creationParamsCodec: const StandardMessageCodec(),
        ),
        CameraLutCarousel(
          controller: widget.controller,
          assetPaths: const [
            'assets/luts/lut1.cube',
            'assets/luts/lut2.cube',
            'assets/luts/lut3.cube',
            'assets/luts/lut4.cube',
            'assets/luts/lut5.cube',
            'assets/luts/lut6.cube',
            'assets/luts/lut7.cube',
            'assets/luts/lut8.cube',
          ],
        ),
      ],
    );
  }
}
