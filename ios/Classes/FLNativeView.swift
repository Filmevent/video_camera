import AVFoundation
import Flutter
import UIKit

class FLNativeViewFactory: NSObject, FlutterPlatformViewFactory {
    private var messenger: FlutterBinaryMessenger
    private var flutterApi: CameraFlutterApi
    private var views: [Int64: FLNativeView] = [:]

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        self.flutterApi = CameraFlutterApi(binaryMessenger: messenger)

        super.init()

        CameraHostApiSetup.setUp(binaryMessenger: messenger, api: CameraHostApiImpl(factory: self))
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        let view = FLNativeView(
            frame: frame,
            viewIdentifier: viewId,
            arguments: args,
            flutterApi: flutterApi
        )
        views[viewId] = view
        return view
    }

    func getView(byId viewId: Int64) -> FLNativeView? {
        return views[viewId]
    }

    func removeView(byId viewId: Int64) {
        views.removeValue(forKey: viewId)
    }
}

class CameraHostApiImpl: CameraHostApi {
    weak var factory: FLNativeViewFactory?

    init(factory: FLNativeViewFactory?) {
        self.factory = factory
    }

    func initializeCamera(viewId: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let view = factory?.getView(byId: viewId) else {
            completion(
                .failure(
                    PigeonError(
                        code: "VIEW_NOT_FOUND",
                        message: "Camera view with ID \(viewId) not found",
                        details: nil
                    )))
            return
        }

        view.initializeCamera { result in
            completion(result)
        }
    }

    func startRecording(viewId: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let view = factory?.getView(byId: viewId) else {
            completion(
                .failure(
                    PigeonError(
                        code: "VIEW_NOT_FOUND",
                        message: "Camera view with ID \(viewId) not found",
                        details: nil
                    )))
            return
        }

        view.startRecording { result in
            completion(result)
        }
    }

    func stopRecording(viewId: Int64, completion: @escaping (Result<String, Error>) -> Void) {
        guard let view = factory?.getView(byId: viewId) else {
            completion(.failure(
                PigeonError(
                    code: "VIEW_NOT_FOUND",
                    message: "Camera view with ID \(viewId) not found",
                    details: nil
                )))
            return
        }

        view.stopRecording(completion: { result in
            switch result {
            case .success(let filePath):
                completion(.success(filePath))
            case .failure(let error):
                completion(.failure(error))
            }
        })
    }


    func pauseCamera(viewId: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let view = factory?.getView(byId: viewId) else {
            completion(
                .failure(
                    PigeonError(
                        code: "VIEW_NOT_FOUND",
                        message: "Camera view with ID \(viewId) not found",
                        details: nil
                    )))
            return
        }

        view.pauseCamera { result in
            completion(result)
        }
    }

    func resumeCamera(viewId: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let view = factory?.getView(byId: viewId) else {
            completion(
                .failure(
                    PigeonError(
                        code: "VIEW_NOT_FOUND",
                        message: "Camera view with ID \(viewId) not found",
                        details: nil
                    )))
            return
        }

        view.resumeCamera { result in
            completion(result)
        }
    }

    func disposeCamera(viewId: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let view = factory?.getView(byId: viewId) else {
            completion(
                .failure(
                    PigeonError(
                        code: "VIEW_NOT_FOUND",
                        message: "Camera view with ID \(viewId) not found",
                        details: nil
                    )))
            return
        }

        view.dispose()
        factory?.removeView(byId: viewId)
        completion(.success(()))
    }
}

class FLNativeView: NSObject, FlutterPlatformView, AVCaptureFileOutputRecordingDelegate {

    private var _view: CameraPreviewView
    private let viewId: Int64
    private let flutterApi: CameraFlutterApi

    private var isInitialized = false
    private var isSessionRunning = false
    private var isDisposed = false

    private var currentRecordingURL: URL?
    private var recordingCompletion: ((Result<String, Error>) -> Void)?

    // MARK: - Camera Properties (moved from ViewController)
    var captureSession: AVCaptureSession!
    var mainCamera: AVCaptureDevice!
    var cameraInput: AVCaptureDeviceInput!
    var microphone: AVCaptureDevice!
    var audioInput: AVCaptureDeviceInput!

    var movieFileOutput: AVCaptureMovieFileOutput!

    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        flutterApi: CameraFlutterApi
    ) {
        self._view = CameraPreviewView()
        self.viewId = viewId
        self.flutterApi = flutterApi
        super.init()
        // iOS views can be created here
        _view.backgroundColor = UIColor.black

    }

    func view() -> UIView {
        return _view
    }

    func initializeCamera(completion: @escaping (Result<Void, Error>) -> Void) {
        NSLog("Called initializeCamera")
        guard !isInitialized else {
            NSLog("Already initialized camera")
            completion(.success(()))
            return
        }
        NSLog("Check permissions")
        checkPermissions { [weak self] result in
            switch result {
            case .success:
                self?.setupAndStartCaptureSession(completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func checkPermissions(completion: @escaping (Result<Void, Error>) -> Void) {
        NSLog("Checking for permission now")
        let cameraAuthStatus = AVCaptureDevice.authorizationStatus(for: .video)
        switch cameraAuthStatus {
        case .authorized:
            completion(.success((())))
        case .denied, .restricted:
            let error = CameraError(
                code: "PERMISSION_DENIED",
                message: "Camera permission denied. Please enable in Settings.",
                details: "Current status: \(cameraAuthStatus.rawValue)"
            )
            flutterApi.onCameraError(viewId: viewId, error: error) { _ in }
            completion(
                .failure(
                    PigeonError(
                        code: error.code,
                        message: error.message,
                        details: error.details
                    )))
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] authorized in
                if authorized {
                    completion(.success(()))
                } else {
                    let error = CameraError(
                        code: "PERMISSION_DENIED",
                        message: "Camera permission denied. Please enable in Settings.",
                        details: "User denied permission"
                    )
                    self?.flutterApi.onCameraError(viewId: self?.viewId ?? 0, error: error) { _ in }
                    completion(
                        .failure(
                            PigeonError(
                                code: error.code,
                                message: error.message,
                                details: error.details
                            )))

                }
            }
        @unknown default:
            let error = CameraError(
                code: "UNKNOWN_ERROR",
                message: "Unknown camera authorization status",
                details: nil
            )
            flutterApi.onCameraError(viewId: viewId, error: error) { _ in }
            completion(.failure(PigeonError(
                code: error.code,
                message: error.message,
                details: error.details
            )))
        }
    }

    func setupAndStartCaptureSession(completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in

            guard let self = self else {return}

            do {

                self.captureSession = AVCaptureSession()
                guard let session = self.captureSession else {
                    throw CameraSetupError.sessionCreationFailed
                }

                session.beginConfiguration()

                if session.canSetSessionPreset(.inputPriority) {
                    session.sessionPreset = .inputPriority
                }

                session.automaticallyConfiguresCaptureDeviceForWideColor = false

                guard let mainCamera = try self.setupInputs() else {
                    throw CameraSetupError.inputSetupFailed
                }
                NSLog("\(mainCamera)")

                if !mainCamera.activeFormat.supportedColorSpaces.contains(.appleLog) {
                    self.captureSession.automaticallyConfiguresCaptureDeviceForWideColor = true
                    if #available(iOS 26.0, *) {
                        if mainCamera.activeFormat.isCinematicVideoCaptureSupported {
                            self.cameraInput.isCinematicVideoCaptureEnabled = true
                        }
                    }
                }
                try self.setupAudioInputs()
                try self.setupOutputs()

                DispatchQueue.main.async {
                    self.setupPreviewLayer()
                }
                // Commit configuration
                session.commitConfiguration()
                // Start running it
                session.startRunning()

                self.isSessionRunning = true
                self.isInitialized = true

                DispatchQueue.main.async {
                    self.flutterApi.onCameraReady(viewId: self.viewId) { _ in}
                    completion(.success(()))
                }
            } catch {
                let CameraError = self.mapToCameraError(error)
                DispatchQueue.main.async{
                    self.flutterApi.onCameraError(viewId: self.viewId, error: CameraError) { _ in}
                    completion(.failure(PigeonError(
                        code: CameraError.code,
                        message: CameraError.message,
                        details: CameraError.details
                    )))
                }
            }

        }
    }

    //MARK: - Recording Methods

    func startRecording(completion: @escaping (Result<Void, Error>) -> Void){
        guard isInitialized else {
            completion(.failure(PigeonError(
                code: "NOT_INITIALIZED",
                message: "Camera not initialized",
                details: nil
            )))
            return
        }
        guard let output = movieFileOutput, !output.isRecording else {
            completion(.failure(PigeonError(
                code: "ALREADY_RECORDING",
                message: "Already recording",
                details: nil
            )))
            return
        }

        let outputFileName = NSUUID().uuidString
        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(outputFileName)
            .appendingPathExtension("mov")

        currentRecordingURL = outputURL
        recordingCompletion = nil

        output.startRecording(to: outputURL, recordingDelegate: self)
        flutterApi.onRecordingStarted(viewId: viewId) { _ in }
        completion(.success(()))
    }

    func stopRecording(completion: @escaping (Result<String, Error>) -> Void){
        guard let output = movieFileOutput, output.isRecording else {
            completion(.failure(PigeonError(
                code: "NOT_RECORDING",
                message: "Not currently recording",
                details: nil
            )))
            return
        }

        recordingCompletion = completion
        output.stopRecording()
    }

    //MARK: - AVCaptureFileOutputRecordingDelegate

    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?){
        if let error = error{
            let cameraError = mapToCameraError(error)
            flutterApi.onCameraError(viewId: viewId, error: cameraError) { _ in }
            recordingCompletion?(.failure(error))
        } else {
            let filePath = outputFileURL.path
            flutterApi.onRecordingStopped(viewId: viewId, filePath: filePath) { _ in }
            recordingCompletion?(.success(filePath))
        }

        recordingCompletion = nil
        currentRecordingURL = nil
    }

    //MARK: - Lifecycle methods

    func pauseCamera(completion: @escaping (Result<Void, Error>) -> Void) {
        guard isSessionRunning else {
            completion(.success(()))
            return
        }

        captureSession?.stopRunning()
        isSessionRunning = false
        completion(.success(()))
    }

    func resumeCamera(completion: @escaping (Result<Void, Error>) -> Void) {
        guard isInitialized, !isSessionRunning else {
            completion(.success(()))
            return
        } 

        captureSession?.startRunning()
        isSessionRunning = true
        completion(.success(()))
    }

    func dispose() {
        guard !isDisposed else { return }
        isDisposed = true

        if let output = movieFileOutput, output.isRecording {
            output.stopRecording()
        }
        
        if isSessionRunning {
            captureSession?.stopRunning()
        }

        captureSession?.inputs.forEach { captureSession?.removeInput($0) }
        captureSession?.outputs.forEach { captureSession?.removeOutput($0) }

        captureSession = nil
        mainCamera = nil
        cameraInput = nil
        microphone = nil
        audioInput = nil
        movieFileOutput = nil
    }

    deinit {
        dispose()
    }

    // MARK: - Error Mapping

    private func mapToCameraError(_ error: Error) -> CameraError {
        if let setupError = error as? CameraSetupError {
            return CameraError(
                code: setupError.code,
                message: setupError.localizedDescription,
                details: String(describing: setupError)
            )
        }

        return CameraError(
            code: "UNKNOWN_ERROR",
            message: error.localizedDescription,
            details: String(describing: error)
        )
    }

    func setupInputs() throws -> AVCaptureDevice? {

        guard let camera = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) 
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraSetupError.noSuitableCamera
        }
        
        mainCamera = camera
        
        do {
            try mainCamera.lockForConfiguration()
            
            if let format = findBestFormat() {
                mainCamera.activeFormat = format
                NSLog("Active format: \(format.formatDescription)")
                NSLog("AppleLog support: \(format.supportedColorSpaces.contains(.appleLog))")
                NSLog("HDR support: \(format.supportedColorSpaces.contains(.HLG_BT2020))")
                NSLog("Stabilization mode: \(format.isVideoStabilizationModeSupported(.cinematicExtended) ? "supported" : "not supported")")
                NSLog("Field of view: \(format.videoFieldOfView)")
            } else {
                NSLog("Could not find optimal format, using default")
            }
            
            mainCamera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            mainCamera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            
            if mainCamera.activeFormat.supportedColorSpaces.contains(.appleLog) {
                mainCamera.activeColorSpace = .appleLog
            } else if mainCamera.activeFormat.supportedColorSpaces.contains(.HLG_BT2020) {
                mainCamera.activeColorSpace = .HLG_BT2020
            }
            
            mainCamera.unlockForConfiguration()
        } catch {
            NSLog("Could not lock device for configuration: \(error)")
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: mainCamera)
            
            guard let session = captureSession, session.canAddInput(input) else {
                throw CameraSetupError.cannotAddInput
            }
            
            cameraInput = input
            session.addInput(input)
            
        } catch let error as CameraSetupError {
            throw error
        } catch {
            throw CameraSetupError.inputSetupFailed
        }
        
        return mainCamera
    }

    func setupAudioInputs() throws {
        guard let mic = AVCaptureDevice.default(for: .audio) else {
            throw CameraSetupError.audioNotAvailable
        }


        microphone = mic

        do {
            let input = try AVCaptureDeviceInput(device: microphone)

            guard let session = captureSession, session.canAddInput(input) else {
                throw CameraSetupError.cannotAddAudioInput
            }

            audioInput = input
            session.addInput(input)

            if #available(iOS 26.0, *) {
                if input.isMultichannelAudioModeSupported(.firstOrderAmbisonics) {
                    input.multichannelAudioMode = .firstOrderAmbisonics
                }
            }
        } catch let error as CameraSetupError {
            throw error
        } catch {
            throw CameraSetupError.audioSetupFailed
        }
    }

    func setupOutputs() throws {
        movieFileOutput = AVCaptureMovieFileOutput()
        
        guard let output = movieFileOutput,
            let session = captureSession,
            session.canAddOutput(output) else {
            throw CameraSetupError.cannotAddOutput
        }
        
        session.addOutput(output)
        
        guard let connection = output.connection(with: .video) else {
            throw CameraSetupError.outputSetupFailed
        }
        
        // Configure stabilization
        connection.preferredVideoStabilizationMode = .cinematicExtended
        
        if #available(iOS 18.0, *) {
            connection.preferredVideoStabilizationMode = .cinematicExtendedEnhanced
        }
        
        NSLog("Active stabilization mode: \(connection.activeVideoStabilizationMode.rawValue)")
        
        // Configure codec
        let availableCodecs = output.availableVideoCodecTypes
        print("Available codecs: \(availableCodecs)")
        
        var codecConfigured = false
        
        if availableCodecs.contains(.proRes422Proxy) {
            output.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.proRes422Proxy], for: connection)
            codecConfigured = true
        } else if availableCodecs.contains(.proRes422) {
            output.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.proRes422], for: connection)
            codecConfigured = true
        } else if availableCodecs.contains(.hevc) {
            output.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.hevc], for: connection)
            codecConfigured = true
        } else if availableCodecs.contains(.h264) {
            output.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.h264], for: connection)
            codecConfigured = true
        }
        
        if !codecConfigured {
            throw CameraSetupError.outputSetupFailed
        }
        
        let settings = output.outputSettings(for: connection)
        NSLog("Output settings: \(settings)")

    }

    func setupPreviewLayer() {
        guard let session = captureSession else { return }
        
        _view.videoPreviewLayer.session = session
        _view.videoPreviewLayer.videoGravity = .resizeAspectFill
        
        if let connection = _view.videoPreviewLayer.connection {
            connection.videoRotationAngle = 0
        }
    }

    func findBestFormat() -> AVCaptureDevice.Format? {
        guard let device = mainCamera else { return nil }

        let formats = device.formats

        func score(_ format: AVCaptureDevice.Format) -> Int {
            let desc = format.formatDescription
            let resolution = CMVideoFormatDescriptionGetDimensions(desc)

            let is4k = resolution.width >= 3840 && resolution.height >= 2160
            let isFullHD = resolution.width >= 1920 && resolution.height >= 1080

            let cinematicextendedStabilization = format.isVideoStabilizationModeSupported(
                .cinematicExtended)
            let cinematicStabilization = format.isVideoStabilizationModeSupported(.cinematic)
            let autoStabilization = format.isVideoStabilizationModeSupported(.auto)

            let appleLog = format.supportedColorSpaces.contains(.appleLog)
            let hdr = format.supportedColorSpaces.contains(.HLG_BT2020)

            var cinematicExtendedEnhancedStabilization = false
            if #available(iOS 18.0, *) {
                cinematicExtendedEnhancedStabilization = format.isVideoStabilizationModeSupported(
                    .cinematicExtendedEnhanced)
            }

            var cinematicVideo = false
            if #available(iOS 26.0, *) {
                cinematicVideo = format.isCinematicVideoCaptureSupported
            }

            var score = 0
            if is4k { score -= 10000 }
            if isFullHD { score += 7000 }
            if appleLog { score += 10000 }
            if cinematicVideo { score += 1000 }
            if hdr { score += 500 }
            if cinematicExtendedEnhancedStabilization { score += 100 }
            if cinematicextendedStabilization { score += 75 }
            if cinematicStabilization { score += 50 }
            if autoStabilization { score += 25 }

            return score
        }

        return
            formats
            .max(by: { score($0) < score($1) })
    }
}

class CameraPreviewView: UIView {
    // Override the layer class to be an AVCaptureVideoPreviewLayer
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }

    // Convenience accessor for the video preview layer
    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }
}

// MARK: - Error Types

enum CameraSetupError: LocalizedError {
    case sessionCreationFailed
    case inputSetupFailed
    case outputSetupFailed
    case noSuitableCamera
    case cannotAddInput
    case cannotAddOutput
    case audioNotAvailable
    case cannotAddAudioInput
    case audioSetupFailed
    
    var code: String {
        switch self {
        case .sessionCreationFailed: return "SESSION_CREATION_FAILED"
        case .inputSetupFailed: return "INPUT_SETUP_FAILED"
        case .outputSetupFailed: return "OUTPUT_SETUP_FAILED"
        case .noSuitableCamera: return "NO_SUITABLE_CAMERA"
        case .cannotAddInput: return "CANNOT_ADD_INPUT"
        case .cannotAddOutput: return "CANNOT_ADD_OUTPUT"
        case .audioNotAvailable: return "AUDIO_NOT_AVAILABLE"
        case .cannotAddAudioInput: return "CANNOT_ADD_AUDIO_INPUT"
        case .audioSetupFailed: return "AUDIO_SETUP_FAILED"
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .sessionCreationFailed: return "Failed to create capture session"
        case .inputSetupFailed: return "Failed to setup camera inputs"
        case .outputSetupFailed: return "Failed to setup camera outputs"
        case .noSuitableCamera: return "No suitable camera found"
        case .cannotAddInput: return "Cannot add input to capture session"
        case .cannotAddOutput: return "Cannot add output to capture session"
        case .audioNotAvailable: return "No microphone available"
        case .cannotAddAudioInput: return "Cannot add audio input to capture session"
        case .audioSetupFailed: return "Failed to setup audio input"
        }
    }
}
