import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:video_camera/src/generated/camera_api.g.dart';

class VideoCameraController extends CameraFlutterApi {
  VideoCameraController() {
    CameraFlutterApi.setUp(this);
  }

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
}
