import Flutter
import UIKit
import AVFoundation

public class VideoCameraPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "video_camera", binaryMessenger: registrar.messenger())
    let instance = VideoCameraPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)

    let api = CameraHostApiImpl()
    CameraHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: api)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

class CameraHostApiImpl: NSObject, CameraHostApi {
  func checkCamera(position: CameraPosition, completion: @escaping (Result<CameraInfo, Error>) -> Void) {
    // Step 1: Check current authorization status
    let authStatus = AVCaptureDevice.authorizationStatus(for: .video)

    var deviceTypes: [AVCaptureDevice.DeviceType] = [
      .builtInWideAngleCamera,
    ]

    if #available(iOS 13.0, *) {
      deviceTypes.append(contentsOf: [.builtInTelephotoCamera, .builtInUltraWideCamera])
    }
    
    // Step 2: Find the requested camera
    let devicePosition: AVCaptureDevice.Position = position == .front ? .front : .back
    let discoverySession = AVCaptureDevice.DiscoverySession(
      deviceTypes: deviceTypes,
      mediaType: .video,
      position: devicePosition
    )

    for device in discoverySession.devices {
      NSLog("========================================")
      NSLog("Camera: \(device.localizedName) - Position: \(device.position.rawValue == 1 ? "Back" : "Front")")
      NSLog("========================================")
      
      // Log all supported formats for this camera
      for (index, format) in device.formats.enumerated() {
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let mediaType = CMFormatDescriptionGetMediaSubType(format.formatDescription)
        let codecType = fourCCToString(mediaType)
        
        NSLog("\nFormat #\(index):")
        NSLog("  Resolution: \(dimensions.width)x\(dimensions.height)")
        NSLog("  Codec: \(codecType)")
        
        // Frame rate ranges
        NSLog("  Frame Rate Ranges:")
        for range in format.videoSupportedFrameRateRanges {
          NSLog("    - Min: \(range.minFrameRate) fps, Max: \(range.maxFrameRate) fps")
        }
        
        // Check ProRes support (iOS 15.0+)
        if #available(iOS 15.0, *) {
          // Check if this format supports ProRes recording
          if format.isVideoHDRSupported {
            NSLog("  HDR: Supported")
          }
          
          // For ProRes, we need to check if the device supports ProRes recording
          // This is a device-level capability, not format-specific
          if device.formats.contains(where: { fmt in
            let mediaSubType = CMFormatDescriptionGetMediaSubType(fmt.formatDescription)
            return mediaSubType == kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange
          }) {
            let mediaSubType = CMFormatDescriptionGetMediaSubType(format.formatDescription)
            NSLog("  Note: This device supports ProRes recording (\(format.description))")
          }
        }
        
        if format.isVideoStabilizationModeSupported(.auto) {
          NSLog("  Stabilization: Supported")
        }

        if #available(iOS 17.0, *) {
          if format.isVideoStabilizationModeSupported(.cinematicExtended) {
            NSLog("  Cinematic Extended Mode: Supported")
          } else {
            NSLog("  Cinematic Extended Mode: Not Supported")
          }
        }

        NSLog("  Field of View: \(format.videoFieldOfView)°")
        NSLog("  Max Zoom: \(format.videoMaxZoomFactor)x")
        
        // ISO and exposure ranges
        NSLog("  ISO Range: \(format.minISO) - \(format.maxISO)")
        NSLog("  Exposure Duration: \(format.minExposureDuration.seconds)s - \(format.maxExposureDuration.seconds)s")
      }
      
      NSLog("\n========================================\n")
    }
    
    let devices = discoverySession.devices
    let isAvailable = !devices.isEmpty
    
    var hasPermission = false
    var errorMessage: String?
    
    switch authStatus {
    case .authorized:
      hasPermission = true
      
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { granted in
        let info = CameraInfo(
          isAvailable: isAvailable,
          hasPermission: granted,
          errorMessage: granted ? nil : "Camera permission denied"
        )
        completion(.success(info))
      }
      return
      
    case .denied:
      hasPermission = false
      errorMessage = "Camera permission denied. Please enable in Settings."
      
    case .restricted:
      hasPermission = false
      errorMessage = "Camera access is restricted."
      
    @unknown default:
      hasPermission = false
      errorMessage = "Unknown authorization status"
    }
    
    let info = CameraInfo(
      isAvailable: isAvailable,
      hasPermission: hasPermission,
      errorMessage: errorMessage
    )
    
    completion(.success(info))
  }
  
  private func fourCCToString(_ fourCC: FourCharCode) -> String {
    let characters = [
      Character(UnicodeScalar((fourCC >> 24) & 0xFF)!),
      Character(UnicodeScalar((fourCC >> 16) & 0xFF)!),
      Character(UnicodeScalar((fourCC >> 8) & 0xFF)!),
      Character(UnicodeScalar(fourCC & 0xFF)!)
    ]
    return String(characters)
  }
}

extension CameraHostApiImpl {
  @available(iOS 15.0, *)
  func getProResRecordingOptions(for device: AVCaptureDevice) -> [String] {
    var proResOptions: [String] = []
  
    
    let proResCodecs = [
      AVVideoCodecType.proRes422,
      AVVideoCodecType.proRes422HQ,
      AVVideoCodecType.proRes422LT,
      AVVideoCodecType.proRes422Proxy,
      AVVideoCodecType.proRes4444
    ]
    
    for codec in proResCodecs {
      proResOptions.append(codec.rawValue)
    }
    
    return proResOptions
  }
  
  func getRecordingCapabilities(for device: AVCaptureDevice, format: AVCaptureDevice.Format) -> [String: Any] {
    let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
    
    var capabilities: [String: Any] = [
      "resolution": "\(dimensions.width)x\(dimensions.height)",
      "frameRates": format.videoSupportedFrameRateRanges.map { 
        ["min": $0.minFrameRate, "max": $0.maxFrameRate] 
      }
    ]
    
    let mediaSubType = CMFormatDescriptionGetMediaSubType(format.formatDescription)
    capabilities["codec"] = fourCCToString(mediaSubType)
    
    if #available(iOS 15.0, *) {
      capabilities["supportsHDR"] = format.isVideoHDRSupported
    }
    
    return capabilities
  }
}