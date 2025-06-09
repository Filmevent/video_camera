import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:video_camera/video_camera.dart';
import 'package:video_camera/video_camera_platform_interface.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _platformVersion = 'Unknown';
  CameraInfo? _frontCameraInfo;
  CameraInfo? _backCameraInfo;
  bool _isLoading = false;
  final _videoCameraPlugin = VideoCamera();

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  Future<void> initPlatformState() async {
    String platformVersion;
    try {
      platformVersion =
          await _videoCameraPlugin.getPlatformVersion() ??
          'Unknown platform version';
    } on PlatformException {
      platformVersion = 'Failed to get platform version.';
    }

    if (!mounted) return;

    setState(() {
      _platformVersion = platformVersion;
    });
  }

  Future<void> _checkCameras() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Check both cameras
      final frontInfo = await _videoCameraPlugin.checkCamera(
        CameraPosition.front,
      );
      final backInfo = await _videoCameraPlugin.checkCamera(
        CameraPosition.back,
      );

      setState(() {
        _frontCameraInfo = frontInfo;
        _backCameraInfo = backInfo;
        _isLoading = false;
      });
    } on PlatformException catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.message}')));
      }
    }
  }

  Widget _buildCameraInfoCard(String title, CameraInfo? info) {
    if (info == null) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  info.isAvailable ? Icons.check_circle : Icons.cancel,
                  color: info.isAvailable ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text('Available: ${info.isAvailable}'),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  info.hasPermission ? Icons.lock_open : Icons.lock,
                  color: info.hasPermission ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                Text('Permission: ${info.hasPermission}'),
              ],
            ),
            if (info.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                info.errorMessage!,
                style: TextStyle(
                  color: Colors.red[700],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Video Camera Plugin Example'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        ),
        body: SingleChildScrollView(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Running on: $_platformVersion',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const Divider(),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.all(32.0),
                  child: CircularProgressIndicator(),
                )
              else ...[
                _buildCameraInfoCard('Front Camera', _frontCameraInfo),
                _buildCameraInfoCard('Back Camera', _backCameraInfo),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isLoading ? null : _checkCameras,
                child: const Text('Check Cameras'),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
