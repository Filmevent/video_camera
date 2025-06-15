import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_camera/video_camera.dart';
import 'package:video_camera_example/core/services/device_orientation_service/device_orientation_provider.dart';
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
        rotationAngle: -90,
        child: Scaffold(
          body: orientation.when(
            data: (orientation) {
              return Stack(
                children: [
                  if (orientation.isPortrait)
                    Center(child: Text('Portrait Mode Detected')),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error:
                (error, stack) => Center(child: Text('Error: $error\n$stack')),
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () {
              // Handle button press
            },
            child: Text('Capture'),
          ),
          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerFloat,
        ),
      ),
    );
  }
}
