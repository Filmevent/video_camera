import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/generated/camera_api.g.dart',
    swiftOut: 'ios/Classes/CameraApi.swift',
    dartPackageName: 'video_camera',
  ),
)
@HostApi()
abstract class CameraHostApi {
  @async
  void initializeCamera(int viewId);

  @async
  void startRecording(int viewId);

  @async
  String stopRecording(int viewId);

  @async
  void pauseCamera(int viewId);

  @async
  void resumeCamera(int viewId);

  @async
  void disposeCamera(int viewId);

  @async
  CameraConfiguration getCameraConfiguration(int viewId);

  @async
  void setLut(int viewId, Uint8List lutData);
}

@FlutterApi()
abstract class CameraFlutterApi {
  void onCameraReady(int viewId);
  void onCameraError(int viewId, CameraError error);
  void onRecordingStarted(int viewId);
  void onRecordingStopped(int viewId, String filePath);
  void onCameraConfiguration(int viewId, CameraConfiguration configuration);
  void onShotTypeUpdated(int viewId, String shotType, double confidence);
}

enum CameraPosition { front, back }

enum VideoCodec { prores422, prores422LT, prores422Proxy, hevc, h264 }

enum StabilizationMode {
  cinematicExtendedEnhanced,
  cinematicExtended,
  cinematic,
  auto,
  off,
}

enum MicrophonePosition { external, back, bottom, front }

enum ResolutionPreset { hd4K, hd1080, hd720, sd540, sd480 }

enum ColorSpace { appleLog, hlgBt2020, srgb }

class CameraConfiguration {
  final VideoCodec videoCodec;
  final StabilizationMode stabilizationMode;
  final MicrophonePosition microphonePosition;
  final ResolutionPreset resolutionPreset;
  final ColorSpace colorSpace;
  final int frameRate;

  CameraConfiguration({
    required this.videoCodec,
    required this.stabilizationMode,
    required this.microphonePosition,
    required this.resolutionPreset,
    required this.colorSpace,
    required this.frameRate,
  });
}

class CameraError {
  final String code;
  final String message;
  final String? details;

  CameraError({required this.code, required this.message, this.details});
}
