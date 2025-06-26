import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_camera/video_camera.dart';
import 'package:video_camera_example/core/services/device_orientation_provider.dart';
import 'package:video_camera_example/manual_orientation_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);

  runApp(ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orientation = ref.watch(deviceOrientationProvider);
    print('Current orientation: ${orientation.value}');
    return MaterialApp(
      home: ManualOrientationController(
        rotationAngle: 90,
        child: CameraScreen(),
      ),
    );
  }
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late final VideoCameraController _controller;

  @override
  void initState() {
    super.initState();
    log("Creating Controller");
    _controller = VideoCameraController();
  }

  @override
  void dispose() {
    // Important: Dispose the controller to release native resources.
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        // Use a ValueListenableBuilder to react to the initialization state.
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Always build the platform view so onPlatformViewCreated runs.
            VideoCameraWidget(controller: _controller),
            // Overlay a spinner until initialization completes.
            ValueListenableBuilder<bool>(
              valueListenable: _controller.isInitialized,
              builder: (context, isInitialized, child) {
                return isInitialized
                    ? const SizedBox.shrink()
                    : const CircularProgressIndicator();
              },
            ),
            ValueListenableBuilder(
              valueListenable: _controller.isRecording,
              builder: (context, isRecording, child) {
                return isRecording
                    ? const SizedBox.shrink()
                    : const Text('PortriatModeDetected');
              },
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _onRecordButtonPressed,
        // Use a ValueListenableBuilder to change the icon based on recording state.
        child: ValueListenableBuilder<bool>(
          valueListenable: _controller.isRecording,
          builder: (context, isRecording, child) {
            return Icon(isRecording ? Icons.stop : Icons.videocam);
          },
        ),
      ),
    );
  }

  void _onRecordButtonPressed() async {
    // Ensure the camera is initialized before trying to record.
    if (!_controller.isInitialized.value) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Camera not ready')));
      return;
    }

    if (_controller.isRecording.value) {
      final filePath = await _controller.stopRecording();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Video saved to: $filePath')));
    } else {
      await _controller.startRecording();
    }
  }
}
