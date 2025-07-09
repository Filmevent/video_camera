import AVFoundation
import MetalKit
import Flutter
import Vision
import CoreML
import UIKit

// MARK: - Flutter view factory -------------------------------------------------

class FLNativeViewFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger
    private let flutterApi: CameraFlutterApi
    private var views: [Int64: FLNativeView] = [:]

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        self.flutterApi = CameraFlutterApi(binaryMessenger: messenger)
        super.init()
        CameraHostApiSetup.setUp(binaryMessenger: messenger, api: CameraHostApiImpl(factory: self))
    }

    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        let view = FLNativeView(frame: frame, viewIdentifier: viewId, arguments: args, flutterApi: flutterApi)
        views[viewId] = view
        return view
    }

    func getView(byId viewId: Int64) -> FLNativeView? { views[viewId] }
    func removeView(byId viewId: Int64) { views.removeValue(forKey: viewId) }
}

// MARK: - Camera host Pigeon glue --------------------------------------------

class CameraHostApiImpl: CameraHostApi {
    weak var factory: FLNativeViewFactory?
    init(factory: FLNativeViewFactory?) { self.factory = factory }

    private func view(for id: Int64, completion: @escaping (Result<FLNativeView, Error>) -> Void) {
        guard let view = factory?.getView(byId: id) else {
            completion(.failure(PigeonError(code: "VIEW_NOT_FOUND", message: "Camera view with ID \(id) not found", details: nil)))
            return
        }
        completion(.success(view))
    }

    // MARK: async wrappers -----------------------------------------------------

    func initializeCamera(viewId: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
        view(for: viewId) { result in
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success(let view):
                Task {
                    do {
                        try await view.initializeCamera()
                        completion(.success(()))
                    } catch { completion(.failure(error)) }
                }
            }
        }
    }
    
    func setLut(viewId: Int64, lutData cubeFileBytes: FlutterStandardTypedData,
                completion: @escaping (Result<Void, Error>) -> Void) {
      view(for: viewId) { result in
        switch result {
          case .success(let v):
            Task { @MainActor in
              do {
                try v.loadLUT(from: cubeFileBytes.data)
                completion(.success(()))
              } catch { completion(.failure(error)) }
            }
          case .failure(let e): completion(.failure(e))
        }
      }
    }
    
    func getCameraConfiguration(
        viewId: Int64,
        completion: @escaping (Result<CameraConfiguration, Error>) -> Void) {
      view(for: viewId) { result in
        switch result {
          case .success(let v) where v.configuration != nil:
            completion(.success(v.configuration!))
          case .success:
            completion(.failure(PigeonError(code: "CONFIG_UNAVAILABLE",
                                            message: "Camera not ready", details: nil)))
          case .failure(let e):
            completion(.failure(e))
        }
      }
    }

    func startRecording(viewId: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
        view(for: viewId) { result in
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success(let view):
                Task {
                    do {
                        try await view.startRecording()
                        completion(.success(()))
                    } catch { completion(.failure(error)) }
                }
            }
        }
    }

    func stopRecording(viewId: Int64, completion: @escaping (Result<String, Error>) -> Void) {
        view(for: viewId) { result in
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success(let view):
                Task {
                    do {
                        let path = try await view.stopRecording()
                        completion(.success(path))
                    } catch { completion(.failure(error)) }
                }
            }
        }
    }

    func pauseCamera(viewId: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
        view(for: viewId) { result in
            switch result {
            case .success(let view):
                view.pauseCamera()
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func resumeCamera(viewId: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
        view(for: viewId) { result in
            switch result {
            case .success(let view):
                view.resumeCamera()
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func disposeCamera(viewId: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
        view(for: viewId) { r in
            switch r {
            case .failure(let error): completion(.failure(error))
            case .success(let view):
                view.dispose(); self.factory?.removeView(byId: viewId); completion(.success(()))
            }
        }
    }
}

// MARK: - Metal view with Core‑Image LUT + video recording --------------------

final class FLNativeView: NSObject, FlutterPlatformView, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureFileOutputRecordingDelegate, MTKViewDelegate {

    // Flutter
    private let _view: CameraPreviewView
    private let viewId: Int64
    private let flutterApi: CameraFlutterApi
    private(set) var configuration: CameraConfiguration?

    // Life‑cycle
    private var isInitialized = false
    private var isSessionRunning = false
    private var isDisposed = false

    // Capture
    private var captureSession: AVCaptureSession!
    private var videoDataOutput: AVCaptureVideoDataOutput!
    private var movieFileOutput: AVCaptureMovieFileOutput!
    private let videoDataOutputQueue = DispatchQueue(label: "video_camera.video_data_queue", qos: .userInitiated)
    private var selectedVideoCodec: AVVideoCodecType = .h264

    // Image processing
    private var lutFilter: CIFilter!
    private var latestImage: CIImage?
    private let inflightSemaphore = DispatchSemaphore(value: 1)
    private var frameCounter = 0

    // Async recording continuation
    private var recordingContinuation: CheckedContinuation<String, Error>?

    private let classificationQueue = DispatchQueue(label: "shot_type_queue",
                                                qos: .userInitiated)


    private lazy var shotModel: VNCoreMLModel? = {
        let frameworkBundle = Bundle(for: FLNativeView.self)
        let resourceBundleURL = frameworkBundle.url(forResource: "video_camera", withExtension: "bundle")
        let resourceBundle = resourceBundleURL.flatMap { Bundle(url: $0) }
        let bundles = [resourceBundle, frameworkBundle].compactMap { $0 }
        
        for bundle in bundles {
            // Try .mlmodelc first since that's what we found
            if let modelURL = bundle.url(forResource: "ShotTypeClassifier", withExtension: "mlmodelc") {
                do {
                    print("📦 Found compiled model at: \(modelURL)")
                    let coreML = try MLModel(contentsOf: modelURL)
                    
                    // Print model details
                    print("📊 Model Description:")
                    print("  - Inputs: \(coreML.modelDescription.inputDescriptionsByName)")
                    print("  - Outputs: \(coreML.modelDescription.outputDescriptionsByName)")
                    print("  - Metadata: \(coreML.modelDescription.metadata)")
                    
                    if let imageConstraint = coreML.modelDescription.inputDescriptionsByName.values.first?.imageConstraint {
                        print("  - Expected image format: \(imageConstraint.pixelFormatType)")
                        print("  - Expected size: \(imageConstraint.pixelsWide) x \(imageConstraint.pixelsHigh)")
                    }
                    
                    return try VNCoreMLModel(for: coreML)
                } catch {
                    print("❌ Failed to load mlmodelc: \(error)")
                }
            }
        }
        
        print("❌ ShotTypeClassifier model not found")
        return nil
    }()

    private lazy var shotRequest: VNCoreMLRequest? = {
        guard let model = shotModel else { return nil }
        
        let request = VNCoreMLRequest(model: model) { [weak self] req, error in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ Shot request error: \(error)")
                return
            }
            
            // Handle MultiArray output from MovieShots model
            if let features = req.results as? [VNCoreMLFeatureValueObservation],
               let outputFeature = features.first(where: { $0.featureName == "output" }),
               let multiArray = outputFeature.featureValue.multiArrayValue {
                
                var logits: [Float] = []
                for i in 0..<multiArray.count {
                    logits.append(Float(truncating: multiArray[i]))
                }
                
                // Apply softmax
                let maxLogit = logits.max() ?? 0
                let expValues = logits.map { exp($0 - maxLogit) }
                let sumExp = expValues.reduce(0, +)
                let probabilities = expValues.map { $0 / sumExp }
                
                if let maxIndex = probabilities.indices.max(by: { probabilities[$0] < probabilities[$1] }) {
                    let labels = ["LS", "FS", "MS", "CS", "ECS"]
                    let fullNames = [
                        "Long Shot",
                        "Full Shot",
                        "Medium Shot",
                        "Close-up",
                        "Extreme Close-up"
                    ]
                    
                    let label = labels[maxIndex]
                    let fullName = fullNames[maxIndex]
                    let confidence = probabilities[maxIndex]
                    
                    // Debug output
                    if confidence > 0.3 { // Only log confident predictions
                        print("🎯 \(label) - \(fullName): \(String(format: "%.1f%%", confidence * 100))")
                        print("   All probabilities: \(probabilities.enumerated().map { "\(labels[$0]): \(String(format: "%.1f%%", $1 * 100))" }.joined(separator: ", "))")
                    }
                    
                    self.sendShotTypeToFlutter(label, prob: Double(confidence))
                }
            }
        }
        
        // CRITICAL: Use scaleFit to see the entire frame
        // This is important for shot type classification!
        request.imageCropAndScaleOption = .scaleFill
        
        
        return request
    }()


    // MARK: init
    init(frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?, flutterApi: CameraFlutterApi) {
        self._view = CameraPreviewView()
        self.viewId = viewId
        self.flutterApi = flutterApi
        super.init()

        _view.delegate = self
        _view.isPaused = true

    }

    func view() -> UIView { _view }

    // MARK: public camera API ---------------------------------------------------

    @MainActor
    func initializeCamera() async throws {
        guard !isInitialized else { return }
        try await checkPermissions()
        try await setupAndStartCaptureSession()
    }

    @MainActor
    func startRecording() async throws {
        guard isInitialized else { throw PigeonError(code: "NOT_INITIALIZED", message: "Camera not initialized", details: nil) }
        guard let output = movieFileOutput, !output.isRecording else { throw PigeonError(code: "ALREADY_RECORDING", message: "Already recording", details: nil) }
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        output.startRecording(to: url, recordingDelegate: self)
        flutterApi.onRecordingStarted(viewId: viewId) { _ in }
    }

    @MainActor
    func stopRecording() async throws -> String {
        guard let output = movieFileOutput, output.isRecording else { throw PigeonError(code: "NOT_RECORDING", message: "Not recording", details: nil) }
        return try await withCheckedThrowingContinuation { continuation in
            recordingContinuation = continuation
            output.stopRecording()
        }
    }

    func pauseCamera() {
        guard isSessionRunning else { return }
        captureSession.stopRunning(); isSessionRunning = false; _view.isPaused = true
    }

    func resumeCamera() {
        guard isInitialized, !isSessionRunning else { return }
        _view.isPaused = false; captureSession.startRunning(); isSessionRunning = true
    }

    func dispose() {
        guard !isDisposed else { return }
        isDisposed = true
        movieFileOutput?.stopRecording()
        if isSessionRunning { captureSession.stopRunning() }
        _view.isPaused = true; _view.delegate = nil
        captureSession.inputs.forEach { captureSession.removeInput($0) }
        captureSession.outputs.forEach { captureSession.removeOutput($0) }
        captureSession = nil
    }

    deinit { dispose() }
    
    // MARK: private helpers -----------------------------------------------------

    private func checkPermissions() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                throw PigeonError(code: "PERMISSION_DENIED", message: "Camera permission denied", details: nil)
            }
        default:
            throw PigeonError(code: "PERMISSION_DENIED", message: "Camera permission denied", details: nil)
        }
    }

    private func setupAndStartCaptureSession() async throws {
        do {
            captureSession = AVCaptureSession()
            captureSession.beginConfiguration()
            captureSession.sessionPreset = .inputPriority
            captureSession.automaticallyConfiguresCaptureDeviceForWideColor = false

            let camera = try setupInputs()
            try setupAudio()
            let _ = try setupOutputs()

            captureSession.commitConfiguration()
            NSLog(camera.activeColorSpace.rawValue.description)
            switch camera.activeColorSpace.rawValue {
            case 0:
                try await loadLUT(named: "rthlut1-17")
                break
            case 2:
                try await loadLUT(named: "rthlut1-17")
                break
            case 3:
                try await loadLUT(named: "rthlut1-17")
                break
            default:
                try await loadLUT(named: "rthlut1-17")
            }
            //try await loadLUT(named: camera.activeColorSpace.rawValue.description)
            captureSession.startRunning()
            
            let conf = makeConfiguration()
            configuration = conf
            await MainActor.run {
                isSessionRunning = true
                isInitialized   = true
                _view.isPaused  = false
                flutterApi.onCameraReady(viewId: viewId) { _ in }
                flutterApi.onCameraConfiguration(viewId: viewId,
                                                 configuration: conf) { _ in }
            }

        } catch {
            let cameraError = mapToCameraError(error)
            await MainActor.run { flutterApi.onCameraError(viewId: viewId, error: cameraError) { _ in } }
            throw PigeonError(code: cameraError.code, message: cameraError.message, details: cameraError.details)
        }
    }

    private func setupInputs() throws -> AVCaptureDevice {
        guard let camera = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraSetupError.noSuitableCamera
        }
        try camera.lockForConfiguration(); defer { camera.unlockForConfiguration() }
        if let fmt = findBestFormat(for: camera) { camera.activeFormat = fmt }
        camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
        camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
        if camera.activeFormat.supportedColorSpaces.contains(.appleLog) {
            camera.activeColorSpace = .appleLog
        } else if camera.activeFormat.supportedColorSpaces.contains(.HLG_BT2020){
            camera.activeColorSpace = .HLG_BT2020
        } else {
            camera.activeColorSpace = .sRGB
        }
        let input = try AVCaptureDeviceInput(device: camera)
        guard captureSession.canAddInput(input) else { throw CameraSetupError.cannotAddInput }
        captureSession.addInput(input)
        
        return camera
    }

    private func setupAudio() throws {
        guard let mic = AVCaptureDevice.default(for: .audio) else { throw CameraSetupError.audioNotAvailable }
        let input = try AVCaptureDeviceInput(device: mic)
        guard captureSession.canAddInput(input) else { throw CameraSetupError.cannotAddAudioInput }
        captureSession.addInput(input)
    }

    private func setupOutputs() throws -> AVCaptureMovieFileOutput {
        videoDataOutput = AVCaptureVideoDataOutput()
        guard captureSession.canAddOutput(videoDataOutput) else { throw CameraSetupError.cannotAddOutput }
        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        let preferred: [OSType] = [kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange, kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange, kCVPixelFormatType_32BGRA]
        if let f = preferred.first(where: videoDataOutput.availableVideoPixelFormatTypes.contains) {
            videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: f]
        }
        captureSession.addOutput(videoDataOutput)

        movieFileOutput = AVCaptureMovieFileOutput()
        guard let output = movieFileOutput, captureSession.canAddOutput(output) else { throw CameraSetupError.cannotAddOutput }
        captureSession.addOutput(output)
        if let conn = output.connection(with: .video) {
            if conn.isVideoStabilizationSupported { conn.preferredVideoStabilizationMode = .cinematicExtended }
            let codecs = output.availableVideoCodecTypes
            if codecs.contains(.proRes422Proxy) {
                selectedVideoCodec = .proRes422Proxy
                output.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.proRes422Proxy], for: conn)
            } else if codecs.contains(.hevc) {
                selectedVideoCodec = .hevc
                output.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.hevc], for: conn)
            }
        }
        return output
    }

    // MARK: LUT -----------------------------------------------------------

    private func parseCube(_ data: Data) throws -> (size: Int, cubeData: Data) {
        guard let text = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "LUT", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid UTF-8"])
        }

        var cube: [Float] = []
        var cubeSize = 0

        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            if line.uppercased().hasPrefix("LUT_3D_SIZE") {
                cubeSize = Int(line.split(separator: " ").last!)!
                cube.reserveCapacity(cubeSize * cubeSize * cubeSize * 4)
                continue
            }
            let rgb = line.split(separator: " ").compactMap(Float.init)
            if rgb.count == 3 { cube.append(contentsOf: rgb + [1]) }
        }
        guard cubeSize > 0, cube.count == cubeSize * cubeSize * cubeSize * 4 else {
            throw NSError(domain: "LUT", code: -2, userInfo: [NSLocalizedDescriptionKey: "Malformed .cube"])
        }
        return (cubeSize, Data(buffer: UnsafeBufferPointer(start: &cube, count: cube.count)))
    }

    @MainActor
    func loadLUT(from data: Data) throws {
        let (size, cubeData) = try parseCube(data)
        applyCube(size: size, data: cubeData)
    }

    @MainActor
    func loadLUT(named name: String = "identity") throws {
        guard let url = Bundle.main.url(forResource: name, withExtension: "cube") else {
            throw NSError(domain: "LUT", code: -3, userInfo: [NSLocalizedDescriptionKey: "Missing LUT asset"])
        }
        try loadLUT(from: try Data(contentsOf: url))
    }

    private func applyCube(size: Int, data: Data) {
        lutFilter = CIFilter(name: "CIColorCube")!
        lutFilter.setValue(size, forKey: "inputCubeDimension")
        lutFilter.setValue(data, forKey: "inputCubeData")
    }

    // MARK: Core‑Image / Metal --------------------------------------------------

    func captureOutput(_ output: AVCaptureOutput,
                    didOutput sampleBuffer: CMSampleBuffer,
                    from connection: AVCaptureConnection) {

        autoreleasepool {
            guard let pixel = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

            // LUT path
            let src = CIImage(cvPixelBuffer: pixel)
            lutFilter.setValue(src, forKey: kCIInputImageKey)
            if let out = lutFilter.outputImage {
                Task { @MainActor in self.latestImage = out }
            }

            // Shot-type classification every 15th frame
            frameCounter &+= 1
            if frameCounter % 15 == 0 {
                guard let request = shotRequest else {
                    if frameCounter % 150 == 0 {
                        print("⚠️ Shot classification skipped - no model loaded")
                    }
                    return
                }
                
                // Print pixel buffer details once
                if frameCounter == 15 {
                    let width = CVPixelBufferGetWidth(pixel)
                    let height = CVPixelBufferGetHeight(pixel)
                    let format = CVPixelBufferGetPixelFormatType(pixel)
                    print("📹 Pixel buffer: \(width)x\(height), format: \(format)")
                }
                
                if let request = shotRequest {
                    classificationQueue.async {
                        let handler = VNImageRequestHandler(cvPixelBuffer: pixel,
                                                            orientation: .up,
                                                            options: [:])
                        try? handler.perform([request])
                    }
                }

            }
        }
    }



    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo url: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let e = error { recordingContinuation?.resume(throwing: e) } else { recordingContinuation?.resume(returning: url.path) }
        recordingContinuation = nil
    }

    // MARK: MTKViewDelegate -----------------------------------------------------

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    let cgColorSpace = CGColorSpaceCreateDeviceRGB()
    var drawableRect = CGRect.zero

    func draw(in view: MTKView) {
        inflightSemaphore.wait(); defer { inflightSemaphore.signal() }

        guard
            let drawable = view.currentDrawable,
            let cmd      = _view.commandQueue.makeCommandBuffer(),
            let src      = latestImage
        else { return }

        // ----- safe guard --------------------------------------------------------
        let w = view.drawableSize.width
        let h = view.drawableSize.height
        guard w > 0, h > 0 else { return }               // <- prevents NaN/∞
        let srcExtent = src.extent
        guard srcExtent.width > 0, srcExtent.height > 0 else { return }

        // ----- centre-crop transform --------------------------------------------
        let scale = max(w / srcExtent.width, h / srcExtent.height)
        let dx = (w - srcExtent.width  * scale) * 0.5 / scale
        let dy = (h - srcExtent.height * scale) * 0.5 / scale

        let tf = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: scale, y: scale)
        let final = src.transformed(by: tf).cropped(to: CGRect(origin: .zero, size: view.drawableSize))

        _view.ciContext.render(final, to: drawable.texture, commandBuffer: cmd,
                               bounds: CGRect(origin: .zero, size: view.drawableSize),
                               colorSpace: cgColorSpace)

        cmd.present(drawable); cmd.commit()

        frameCounter &+= 1
        if frameCounter & 0xFF == 0 { _view.ciContext.clearCaches() }
    }


    // MARK: misc helpers --------------------------------------------------------

    private func findBestFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        device.formats.max { score($0) < score($1) }
    }
    private func score(_ f: AVCaptureDevice.Format) -> Int {
        let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
        var s = 0
        if d.width >= 1920 && d.height >= 1080 { s += 7_000 }
        if f.supportedColorSpaces.contains(.appleLog) { s += 10_000 }
        if f.isVideoStabilizationModeSupported(.cinematicExtended) { s += 75 }
        return s
    }

    private func mapToCameraError(_ error: Error) -> CameraError {
        if let e = error as? CameraSetupError { return CameraError(code: e.code, message: e.localizedDescription, details: String(describing: e)) }
        return CameraError(code: "UNKNOWN_ERROR", message: error.localizedDescription, details: String(describing: error))
    }
    
    private func makeConfiguration() -> CameraConfiguration {
        let camera      = (captureSession.inputs.first as? AVCaptureDeviceInput)!.device
        let format      = camera.activeFormat
        let dims        = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let conn        = movieFileOutput?.connection(with: .video)

        // -------- enum mapping helpers ----------
        func mapCodec(_ t: AVVideoCodecType) -> VideoCodec {
            switch t {
            case .proRes422Proxy: return .prores422Proxy
            case .hevc:           return .hevc
            default:              return .h264
            }
        }

        func mapStab(_ m: AVCaptureVideoStabilizationMode) -> StabilizationMode {
            switch m {
            case .cinematicExtendedEnhanced: return .cinematicExtendedEnhanced
            case .cinematicExtended:         return .cinematicExtended
            case .cinematic:                 return .cinematic
            case .auto:                      return .auto
            default:                         return .off
            }
        }

        func mapMic(_ pos: AVCaptureDevice.Position) -> MicrophonePosition {
            switch pos {
            case .back:  return .back
            case .front: return .front
            default:     return .bottom   // bottom mic equals .unspecified on iPhone
            }
        }

        func mapRes(_ w: Int32, _ h: Int32) -> ResolutionPreset {
            if w >= 3840 || h >= 2160 { return .hd4K }
            if w >= 1920 || h >= 1080 { return .hd1080 }
            if w >= 1280 || h >=  720 { return .hd720 }
            if w >=  960 || h >=  540 { return .sd540 }
            return .sd480
        }

        func mapColor(_ cs: AVCaptureColorSpace) -> ColorSpace {
            switch cs {
            case .appleLog: return .appleLog
            case .HLG_BT2020: return .hlgBt2020
            default: return .srgb
            }
        }
        // ----------------------------------------

        let fps = Int64(30)

        return CameraConfiguration(
            videoCodec:        mapCodec(selectedVideoCodec),
            stabilizationMode: mapStab(conn?.activeVideoStabilizationMode ?? .off),
            microphonePosition: mapMic((captureSession.inputs
                                       .compactMap { $0 as? AVCaptureDeviceInput }
                                       .first { $0.device.hasMediaType(.audio) })?
                                       .device.position ?? .unspecified),
            resolutionPreset:  mapRes(dims.width, dims.height),
            colorSpace:        mapColor(camera.activeColorSpace),
            frameRate:         fps
        )
    }
}

// MARK: - Custom MTKView with tuned CIContext ----------------------------------

final class CameraPreviewView: MTKView {
    let commandQueue: MTLCommandQueue
    let ciContext: CIContext

    init() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { fatalError("Metal not supported") }
        commandQueue = queue
        ciContext = CIContext(mtlDevice: device, options: [
            .workingColorSpace : CGColorSpace(name: CGColorSpace.sRGB)! ,
            .cacheIntermediates: false
        ])
        super.init(frame: .zero, device: device)
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = false
        enableSetNeedsDisplay = false
        isPaused = true
        preferredFramesPerSecond = 30
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - Error enum -----------------------------------------------------------

enum CameraSetupError: LocalizedError {
    case sessionCreationFailed, inputSetupFailed, outputSetupFailed, noSuitableCamera, cannotAddInput, cannotAddOutput, audioNotAvailable, cannotAddAudioInput, audioSetupFailed
    var code: String {
        switch self {
        case .sessionCreationFailed: return "SESSION_CREATION_FAILED"
        case .inputSetupFailed:     return "INPUT_SETUP_FAILED"
        case .outputSetupFailed:    return "OUTPUT_SETUP_FAILED"
        case .noSuitableCamera:     return "NO_SUITABLE_CAMERA"
        case .cannotAddInput:       return "CANNOT_ADD_INPUT"
        case .cannotAddOutput:      return "CANNOT_ADD_OUTPUT"
        case .audioNotAvailable:    return "AUDIO_NOT_AVAILABLE"
        case .cannotAddAudioInput:  return "CANNOT_ADD_AUDIO_INPUT"
        case .audioSetupFailed:     return "AUDIO_SETUP_FAILED"
        }
    }
    var errorDescription: String? { code.replacingOccurrences(of: "_", with: " ").capitalized }
}

extension FLNativeView {
    // must accept BOTH label and probability
    private func sendShotTypeToFlutter(_ label: String, prob: Double) {
        flutterApi.onShotTypeUpdated(
            viewId: viewId,
            shotType: label,
            confidence: prob   // matches the Pigeon API
        ) { _ in }
    }
}
