import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:native_device_orientation/native_device_orientation.dart';

// The main provider - provides initial value immediately
final deviceOrientationProvider = StreamProvider<NativeDeviceOrientation>((
  ref,
) async* {
  final communicator = NativeDeviceOrientationCommunicator();

  // Emit initial orientation immediately
  yield await communicator.orientation(useSensor: false);

  // Then emit all changes
  yield* communicator.onOrientationChanged(useSensor: true);
});

// For synchronous access (never returns null)
final currentOrientationProvider = Provider<NativeDeviceOrientation>((ref) {
  return ref.watch(deviceOrientationProvider).valueOrNull ??
      NativeDeviceOrientation
          .landscapeLeft; // Default for landscape-locked apps
});

// Extensions for convenience
extension OrientationExtensions on NativeDeviceOrientation {
  bool get isPortrait =>
      this == NativeDeviceOrientation.portraitUp ||
      this == NativeDeviceOrientation.portraitDown;

  bool get isLandscape =>
      this == NativeDeviceOrientation.landscapeLeft ||
      this == NativeDeviceOrientation.landscapeRight;

  // UI rotation needed when device is in portrait but app is landscape-locked
  double get uiRotationAngle {
    if (isLandscape) return 0;

    switch (this) {
      case NativeDeviceOrientation.portraitUp:
        return -90; // Rotate UI 90° counter-clockwise
      case NativeDeviceOrientation.portraitDown:
        return 90; // Rotate UI 90° clockwise
      default:
        return 0;
    }
  }
}
