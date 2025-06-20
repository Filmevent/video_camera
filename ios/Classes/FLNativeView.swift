import AVFoundation
import MetalKit
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
            completion(.failure(PigeonError(code: "VIEW_NOT_FOUND", message: "Camera view with ID \(viewId) not found", details: nil)))
            return
        }

        // Create a Task to run the async function
        Task {
            do {
                try await view.initializeCamera()
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func startRecording(viewId: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let view = factory?.getView(byId: viewId) else {
            completion(.failure(PigeonError(code: "VIEW_NOT_FOUND", message: "Camera view with ID \(viewId) not found", details: nil)))
            return
        }
        
        Task {
            do {
                try await view.startRecording()
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func stopRecording(viewId: Int64, completion: @escaping (Result<String, Error>) -> Void) {
        guard let view = factory?.getView(byId: viewId) else {
            completion(.failure(PigeonError(code: "VIEW_NOT_FOUND", message: "Camera view with ID \(viewId) not found", details: nil)))
            return
        }

        Task {
            do {
                let filePath = try await view.stopRecording()
                completion(.success(filePath))
            } catch {
                completion(.failure(error))
            }
        }
    }


    func pauseCamera(viewId: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let view = factory?.getView(byId: viewId) else {
            completion(.failure(PigeonError(code: "VIEW_NOT_FOUND", message: "Camera view with ID \(viewId) not found", details: nil)))
            return
        }

        view.pauseCamera()
        completion(.success(()))
    }

    func resumeCamera(viewId: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let view = factory?.getView(byId: viewId) else {
            completion(.failure(PigeonError(code: "VIEW_NOT_FOUND", message: "Camera view with ID \(viewId) not found", details: nil)))
            return
        }

        view.resumeCamera()
        completion(.success(()))
    }

    func disposeCamera(viewId: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let view = factory?.getView(byId: viewId) else {
            completion(.failure(PigeonError(code: "VIEW_NOT_FOUND", message: "Camera view with ID \(viewId) not found", details: nil)))
            return
        }

        view.dispose()
        factory?.removeView(byId: viewId)
        completion(.success(()))
    }
}
class FLNativeView: NSObject, FlutterPlatformView, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureFileOutputRecordingDelegate, MTKViewDelegate {

    private var _view: CameraPreviewView
    private let viewId: Int64
    private let flutterApi: CameraFlutterApi

    private var isInitialized = false
    private var isSessionRunning = false
    private var isDisposed = false

    var captureSession: AVCaptureSession!
    var mainCamera: AVCaptureDevice!
    var cameraInput: AVCaptureDeviceInput!
    var microphone: AVCaptureDevice!
    var audioInput: AVCaptureDeviceInput!
    
    private var recordingContinuation: CheckedContinuation<String, Error>?

    // Outputs for both recording and preview
    var movieFileOutput: AVCaptureMovieFileOutput!
    private var videoDataOutput: AVCaptureVideoDataOutput!
    private var videoDataOutputQueue: DispatchQueue!
    
    private var lutFilter: CIFilter?
        
    private let inflightSemaphore = DispatchSemaphore(value: 3)

    @MainActor private var latestImage: CIImage?

    init(frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?, flutterApi: CameraFlutterApi) {
        self._view = CameraPreviewView()
        self.viewId = viewId
        self.flutterApi = flutterApi
        super.init()
        self.videoDataOutputQueue = DispatchQueue(label: "video_camera.video_data_queue", qos: .userInitiated)
        self._view.delegate = self
        loadLUT()
    }


    // Replace the entire existing loadLUT() function with this one.
    func loadLUT(named lutName: String = "rthlut1-33") {
        // 1. Find the LUT file in the app's bundle.
        guard let url = Bundle.main.url(forResource: lutName, withExtension: "cube") else {
            print("Error: LUT file '\(lutName).cube' not found in bundle.")
            return
        }

        // 2. Read the file contents into a single string.
        guard let fileContents = try? String(contentsOf: url, encoding: .utf8) else {
            print("Error: Could not read LUT file contents.")
            return
        }

        // 3. Parse the file.
        let lines = fileContents.components(separatedBy: .newlines)
        var cubeDimension = 0
        var cubeData: [Float] = []
        
        NSLog("Found LUT")

        // Iterate over each line of the file.
        for line in lines {
            // Skip comments and empty lines.
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }

            // Find the line that defines the LUT size (e.g., "LUT_3D_SIZE 33").
            if line.uppercased().hasPrefix("LUT_3D_SIZE") {
                NSLog("Found LUT SIZE")
                // Split the line by spaces and get the last component, which should be the size.
                if let sizeString = line.split(separator: " ").last, let size = Int(sizeString) {
                    cubeDimension = size
                    // Pre-allocate memory for the cube data for better performance.
                    cubeData.reserveCapacity(cubeDimension * cubeDimension * cubeDimension * 4)
                }
            }
            // For all other lines, assume they are color data.
            else {
                // Split the line into R, G, B components.
                let components = line.split(separator: " ").compactMap { Float($0) }
                
                // A valid data line should have exactly 3 float components (R, G, B).
                if components.count == 3 {
                    cubeData.append(contentsOf: components)
                    // Append the Alpha channel value. .cube files only contain RGB.
                    // The CIColorCube filter requires RGBA.
                    cubeData.append(1.0)
                }
            }
        }

        // 4. Validate the parsed data.
        guard cubeDimension > 0, !cubeData.isEmpty else {
            print("Error: Failed to parse LUT file. Check file format for LUT_3D_SIZE and data lines.")
            return
        }
        
        // The total number of expected values is (size^3) * 4 (for RGBA).
        let expectedCount = cubeDimension * cubeDimension * cubeDimension * 4
        if cubeData.count != expectedCount {
            print("Error: LUT data count (\(cubeData.count)) does not match expected count (\(expectedCount)). The file may be corrupt.")
            return
        }

        // 5. Create the CIColorCube filter with the loaded data.
        self.lutFilter = CIFilter(
            name: "CIColorCube",
            parameters: [
                "inputCubeDimension": cubeDimension,
                // Convert the [Float] array into the Data object the filter expects.
                "inputCubeData": Data(buffer: UnsafeBufferPointer(start: &cubeData, count: cubeData.count))
            ]
        )
        
        NSLog("Successfully loaded LUT '\(lutName).cube' with dimension \(cubeDimension).")
    }

    func view() -> UIView {
        return _view
    }

    // REFACTORED: initializeCamera now uses async/await
    func initializeCamera() async throws {
        NSLog("Called initializeCamera")
        guard !isInitialized else {
            NSLog("Already initialized camera")
            return
        }
        NSLog("Check permissions")
        try await checkPermissions()
        try await setupAndStartCaptureSession()
    }

    // REFACTORED: checkPermissions now uses async/await
    func checkPermissions() async throws {
        NSLog("Checking for permission now")
        let cameraAuthStatus = AVCaptureDevice.authorizationStatus(for: .video)
        switch cameraAuthStatus {
        case .authorized:
            return // Permission already granted
        case .denied, .restricted:
            let error = CameraError(code: "PERMISSION_DENIED", message: "Camera permission denied. Please enable in Settings.", details: "Current status: \(cameraAuthStatus.rawValue)")
            flutterApi.onCameraError(viewId: viewId, error: error) { _ in }
            throw PigeonError(code: error.code, message: error.message, details: error.details)
        case .notDetermined:
            // NEW: Await the permission request instead of using a callback
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted {
                let error = CameraError(code: "PERMISSION_DENIED", message: "Camera permission denied. Please enable in Settings.", details: "User denied permission")
                self.flutterApi.onCameraError(viewId: self.viewId, error: error) { _ in }
                throw PigeonError(code: error.code, message: error.message, details: error.details)
            }
        @unknown default:
            let error = CameraError(code: "UNKNOWN_ERROR", message: "Unknown camera authorization status", details: nil)
            flutterApi.onCameraError(viewId: viewId, error: error) { _ in }
            throw PigeonError(code: error.code, message: error.message, details: error.details)
        }
    }

    // REFACTORED: setupAndStartCaptureSession is now a nonisolated async function
    // It is marked nonisolated to indicate it can run on any thread, similar to your original DispatchQueue.global().async
    nonisolated func setupAndStartCaptureSession() async throws {
        do {
            self.captureSession = AVCaptureSession()
            guard let session = self.captureSession else { throw CameraSetupError.sessionCreationFailed }

            session.beginConfiguration()
            if session.canSetSessionPreset(.inputPriority) { session.sessionPreset = .inputPriority }
            session.automaticallyConfiguresCaptureDeviceForWideColor = false

            guard let mainCamera = try self.setupInputs() else { throw CameraSetupError.inputSetupFailed }
            
            if !mainCamera.activeFormat.supportedColorSpaces.contains(.appleLog) {
                 self.captureSession.automaticallyConfiguresCaptureDeviceForWideColor = true
                 if #available(iOS 26.0, *) {
                     //if mainCamera.activeFormat.isCinematicVideoCaptureSupported {
                     //    self.cameraInput.isCinematicVideoCaptureEnabled = true
                     //}
                 }
            }
            try self.setupAudioInputs()
            try self.setupOutputs()
            
            // NEW: Switch to the main actor for UI updates
            //await MainActor.run {
            //    self.setupPreviewLayer()
            //}

            session.commitConfiguration()
            session.startRunning()

            // These properties should be accessed safely. Using an Actor or locks would be a good next step.
            await MainActor.run {
                self.isSessionRunning = true
                self.isInitialized = true
                
                self._view.isPaused = false
                
                self.flutterApi.onCameraReady(viewId: self.viewId) { _ in }
            }
        } catch {
            let cameraError = self.mapToCameraError(error)
            await MainActor.run {
                self.flutterApi.onCameraError(viewId: self.viewId, error: cameraError) { _ in }
            }
            throw PigeonError(code: cameraError.code, message: cameraError.message, details: cameraError.details)
        }
    }

    // MARK: - Async Recording Methods

    // REFACTORED: startRecording now async
    func startRecording() async throws {
        guard isInitialized else { throw PigeonError(code: "NOT_INITIALIZED", message: "Camera not initialized", details: nil) }
        guard let output = movieFileOutput, !output.isRecording else { throw PigeonError(code: "ALREADY_RECORDING", message: "Already recording", details: nil) }

        let outputFileName = NSUUID().uuidString
        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(outputFileName).appendingPathExtension("mov")

        // FIXED: Use the correct delegate method
        output.startRecording(to: outputURL, recordingDelegate: self)
        
        await MainActor.run {
            flutterApi.onRecordingStarted(viewId: viewId) { _ in }
        }
    }

    // REFACTORED: stopRecording now uses a continuation to await the delegate callback
    func stopRecording() async throws -> String {
        guard let output = movieFileOutput, output.isRecording else {
            throw PigeonError(code: "NOT_RECORDING", message: "Not currently recording", details: nil)
        }
        
        // NEW: Await the result from the delegate method
        return try await withCheckedThrowingContinuation { continuation in
            self.recordingContinuation = continuation
            output.stopRecording()
        }
    }

    // MARK: - Lifecycle methods (now synchronous as they are fast)
    
    func pauseCamera() {
        guard isSessionRunning else { return }
        captureSession?.stopRunning()
        isSessionRunning = false
        _view.isPaused = true // <-- ADD THIS to stop the render loop
    }

    func resumeCamera() {
        guard isInitialized, !isSessionRunning else { return }
        _view.isPaused = false // <-- ADD THIS to restart the render loop
        captureSession?.startRunning()
        isSessionRunning = true
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

        _view.isPaused = true
        
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
        videoDataOutput = AVCaptureVideoDataOutput()
        if captureSession.canAddOutput(videoDataOutput){
            captureSession.addOutput(videoDataOutput)
            videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)

            // ------------------- FINAL WORKING SOLUTION -------------------
            // Get the list of supported formats as UInt32 numbers
            // Note: We are using the property name you found to be working.
            let supportedPixelFormats = videoDataOutput.availableVideoPixelFormatTypes.map { ($0 as! NSNumber).uint32Value }

            // Set our desired video settings
            var newVideoSettings: [String: Any]?
            
            // Check if our preferred BGRA format is supported.
            if supportedPixelFormats.contains(kCVPixelFormatType_32BGRA) {
                // If yes, set it. This is best for Core Image performance.
                newVideoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                NSLog("Using preferred BGRA format for preview.")
                
            } else if supportedPixelFormats.contains(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) {
                // If BGRA is not available, fall back to a common YUV format.
                // Core Image can still handle this efficiently.
                newVideoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
                NSLog("BGRA not supported. Using YUV 420v format for preview.")
                
            } else {
                // If neither is available, we don't set any specific format and let the system decide.
                NSLog("Neither BGRA nor 420v is supported. Using default video settings for preview.")
            }
            
            if let settings = newVideoSettings {
                videoDataOutput.videoSettings = settings
            }
            // ----------------- END OF FINAL SOLUTION -----------------

        } else {
            throw CameraSetupError.cannotAddOutput
        }

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

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // 1. Try to acquire the semaphore. If we can't get it immediately,
        // it means the GPU is still busy with previous frames.
        // In this case, we simply drop the current frame and return.
        // This is the key to preventing back-pressure and stutters.
        guard inflightSemaphore.wait(timeout: .now()) == .success else {
            // print("Dropping frame, GPU is busy.")
            return
        }

        // 2. We now have a "slot". Proceed with processing.
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            inflightSemaphore.signal() // MUST release the slot if we fail
            return
        }

        let sourceImage = CIImage(cvPixelBuffer: pixelBuffer)
        lutFilter?.setValue(sourceImage, forKey: kCIInputImageKey)
        
        guard let filteredImage = lutFilter?.outputImage else {
            inflightSemaphore.signal() // MUST release the slot if we fail
            return
        }

        // 3. Dispatch the render task to the main thread where the MTKView runs.
        // We pass the semaphore along so the main thread knows to signal it upon completion.
        DispatchQueue.main.async {
            // The `filteredImage` still points to the CVPixelBuffer, but that's okay.
            // The semaphore guarantees the buffer is still valid when this block executes
            // and when the GPU eventually reads it.
            self.latestImage = filteredImage
            
            // We no longer need to explicitly call .draw() because the view is un-paused.
            // The `draw(in:)` method will pick up `latestImage` on its next cycle.
            
            // IMPORTANT: The semaphore is now signaled from within `draw(in:)`'s completion handler.
        }
    }


    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            let cameraError = mapToCameraError(error)
            flutterApi.onCameraError(viewId: viewId, error: cameraError) { _ in }
            recordingContinuation?.resume(throwing: error)
        } else {
            let filePath = outputFileURL.path
            flutterApi.onRecordingStopped(viewId: viewId, filePath: filePath) { _ in }
            recordingContinuation?.resume(returning: filePath)
        }
        recordingContinuation = nil
    }
    /*
    func setupPreviewLayer() {
        guard let session = captureSession else { return }
        
        _view.videoPreviewLayer.session = session
        _view.videoPreviewLayer.videoGravity = .resizeAspectFill
        
        if let connection = _view.videoPreviewLayer.connection {
            connection.videoRotationAngle = 0
        }
    } */

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
            //if #available(iOS 26.0, *) {
            //    cinematicVideo = format.isCinematicVideoCaptureSupported
            //}

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
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // This delegate method is called when the view's size changes.
        // You can handle resizing logic here if needed.
    }

    func draw(in view: MTKView) {
        // Since captureOutput is now blocking, we are guaranteed that
        // latestFilteredImage will not be written to while we are here.
        // However, it might be nil if the first frame hasn't arrived.
        guard let imageToRender = self.latestImage else {
            NSLog("Dropped Frame \(Date())")
            return
        }

        guard let commandBuffer = _view.commandQueue.makeCommandBuffer(),
              let drawable = view.currentDrawable else {
            // This can happen. If it does, we can't render, and we can't add a
            // completion handler, so we can't signal. This would cause a deadlock.
            // It's a rare edge case, but to be safe, we should handle it.
            // For now, we assume it succeeds. A more robust solution might be needed
            // if this becomes a problem.
            return
        }

        // IMPORTANT: Add the completion handler BEFORE you commit the buffer.
        // This handler will be called by the system on a background thread
        // AFTER the GPU has finished executing the command buffer.
        commandBuffer.addCompletedHandler { [weak self] _ in
            // Signal the semaphore to allow the next frame to be processed.
            self?.inflightSemaphore.signal()
        }

        let sourceExtent = imageToRender.extent
            let drawableRect = CGRect(origin: .zero, size: view.drawableSize)
            let sourceAspect = sourceExtent.width / sourceExtent.height
            let drawableAspect = drawableRect.width / drawableRect.height
            let scale = (sourceAspect > drawableAspect) ? (drawableRect.height / sourceExtent.height) : (drawableRect.width / sourceExtent.width)
            let scaledSize = CGSize(width: sourceExtent.width * scale, height: sourceExtent.height * scale)
            let translationX = (drawableRect.width - scaledSize.width) / 2.0
            let translationY = (drawableRect.height - scaledSize.height) / 2.0

        let transform = CGAffineTransform(translationX: -sourceExtent.minX, y: -sourceExtent.minY)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: translationX, y: translationY))

        let finalImage = imageToRender
            .transformed(by: transform)
            .cropped(to: drawableRect)

        // 4. Define the render destination.
        let destination = CIRenderDestination(
            width: Int(drawableRect.width),
            height: Int(drawableRect.height),
            pixelFormat: view.colorPixelFormat,
            commandBuffer: commandBuffer) { () -> MTLTexture in
                return drawable.texture
        }
 // your destination setup

        do {
            try _view.ciContext.startTask(toRender: finalImage, to: destination)
        } catch {
            print("Error rendering image in draw(in:): \(error.localizedDescription)")
            // If the render task fails, we must still signal to prevent deadlock.
            inflightSemaphore.signal()
        }

        // Present the drawable and commit the command buffer to the GPU.
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }


}

class CameraPreviewView: MTKView {

    let commandQueue: MTLCommandQueue
    let ciContext: CIContext

    init() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            fatalError("Metal is not supported on this device")
        }
        self.commandQueue = commandQueue
        
        self.ciContext = CIContext(mtlDevice: device, options: [
                    .workingColorSpace: NSNull()
                ])
        
        super.init(frame: .zero, device: device)
        
        self.colorPixelFormat = .bgra8Unorm
        self.framebufferOnly = false
        self.autoResizeDrawable = true
        self.contentMode = .scaleAspectFill
        
        // --- CORRECT CONFIGURATION ---
        // Let the view manage its own display link timer.
        self.isPaused = false
        // You are not using a manual trigger, so this must be false.
        self.enableSetNeedsDisplay = false
        // Hint the desired frame rate. It will sync to the display, but this is good practice.
        self.preferredFramesPerSecond = 30
        // -----------------------------
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
