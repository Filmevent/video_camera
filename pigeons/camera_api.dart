import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/generated/camera_api.g.dart',
    swiftOut: 'ios/Classes/CameraApi.swift',
    dartPackageName: 'video_camera',
  ),
)
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

enum ResolutionPreset { hd4K, hd1080p, hd720p, sd540p, sd480p }

enum ColorSpace { appleLog, hlgBt2020, srgb }

class CameraConfiguration {
  final CameraPosition position;
  final VideoCodec videoCodec;
  final StabilizationMode stabilizationMode;
  final MicrophonePosition microphonePosition;
  final ResolutionPreset resolutionPreset;
  final ColorSpace colorSpace;
  final int frameRate;

  CameraConfiguration({
    this.position = CameraPosition.back,
    this.videoCodec = VideoCodec.hevc,
    this.stabilizationMode = StabilizationMode.auto,
    this.microphonePosition = MicrophonePosition.back,
    this.resolutionPreset = ResolutionPreset.hd1080p,
    this.colorSpace = ColorSpace.srgb,
    this.frameRate = 30,
  });
}

class CameraInfo {
  final bool isAvailable;
  final bool hasPermission;
  final String? errorMessage;

  CameraInfo({
    required this.isAvailable,
    required this.hasPermission,
    this.errorMessage,
  });
}

@HostApi()
abstract class CameraHostApi {
  @async
  CameraInfo checkCamera(CameraPosition position);
}
