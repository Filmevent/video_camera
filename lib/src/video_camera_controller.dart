import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:video_camera/src/generated/camera_api.g.dart';

class ShotTypeEvent {
  final String label;
  final double confidence;
  ShotTypeEvent(this.label, this.confidence);
}

class VideoCameraController extends CameraFlutterApi {
  VideoCameraController() {
    CameraFlutterApi.setUp(this);
  }
  final _shotStream = StreamController<ShotTypeEvent>.broadcast();
  Stream<ShotTypeEvent> get shotTypes => _shotStream.stream;

  final CameraHostApi _hostApi = CameraHostApi();
  int? _viewId;

  final ValueNotifier<bool> isInitialized = ValueNotifier(false);
  final ValueNotifier<bool> isRecording = ValueNotifier(false);
  final ValueNotifier<CameraError?> error = ValueNotifier(null);

  Future<void> initialize(int viewId) async {
    if (isInitialized.value) {
      return;
    }
    _viewId = viewId;
    try {
      await _hostApi.initializeCamera(viewId);
    } on Exception catch (e) {
      debugPrint("Failed to send initialize command: $e");
    }
  }

  Future<void> setLut(Uint8List bytes) async {
    final id = _viewId;
    if (id == null) return;
    await _hostApi.setLut(id, bytes);
  }

  Future<void> setLutFromAsset(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    await setLut(data.buffer.asUint8List());
  }

  Future<void> startRecording() async {
    final viewId = _viewId;
    if (viewId == null || !isInitialized.value || isRecording.value) {
      return;
    }
    await _hostApi.startRecording(viewId);
  }

  Future<String?> stopRecording() async {
    final viewId = _viewId;
    if (viewId == null || !isInitialized.value || !isRecording.value) {
      return null;
    }
    final path = await _hostApi.stopRecording(viewId);
    return path;
  }

  Future<void> pauseCamera() async {
    final viewId = _viewId;
    if (viewId == null || !isInitialized.value) {
      return;
    }
    await _hostApi.pauseCamera(viewId);
  }

  Future<void> resumeCamera() async {
    final viewId = _viewId;
    if (viewId == null || !isInitialized.value) {
      return;
    }
    await _hostApi.resumeCamera(viewId);
  }

  void dispose() {
    if (_viewId != null) {
      _hostApi.disposeCamera(_viewId!);
    }
    isInitialized.dispose();
    isRecording.dispose();
    error.dispose();
  }

  @override
  void onCameraError(int viewId, CameraError error) {
    if (viewId == _viewId) {
      this.error.value = error;
      debugPrint("Native Camera Error: ${error.code} - ${error.message}");
    }
  }

  @override
  void onCameraReady(int viewId) {
    if (viewId == _viewId) {
      isInitialized.value = true;
    }
  }

  @override
  void onRecordingStarted(int viewId) {
    if (viewId == _viewId) {
      isRecording.value = true;
    }
  }

  @override
  void onRecordingStopped(int viewId, String filePath) {
    if (viewId == _viewId) {
      isRecording.value = false;
      debugPrint('Recording stopped. File saved at: $filePath');
    }
  }

  @override
  void onCameraConfiguration(int viewId, CameraConfiguration configuration) {
    // TODO: implement onCameraConfiguration
  }
  
  @override
  void onShotTypeUpdated(int viewId, String shotType, double confidence) {
    if (viewId == _viewId) {
      _shotStream.add(ShotTypeEvent(shotType, confidence));
    }
  }
}
