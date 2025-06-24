import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:video_camera/src/video_camera_controller.dart';

class CameraLutCarousel extends StatelessWidget {
  const CameraLutCarousel({
    super.key,
    required this.controller,
    required this.assetPaths,
    this.heightFactor = .15,
  });

  final VideoCameraController controller;
  final List<String> assetPaths;
  final double heightFactor; // 0.25 = bottom quarter

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: Alignment.bottomCenter,
      heightFactor: heightFactor,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.transparent, Colors.black54],
          ),
        ),
        child: CarouselView.weighted(
          controller: CarouselController(initialItem: 3),
          flexWeights: const [1, 2, 6, 2, 1], // multi-browse 6-2-1
          onTap: (index) async {
            // <- this is the trigger
            final data = await rootBundle.load(assetPaths[index]);
            await controller.setLut(data.buffer.asUint8List());
          },
          children: List.generate(assetPaths.length, (i) => _tile(i)),
        ),
      ),
    );
  }

  Widget _tile(int i) => Container(
    decoration: BoxDecoration(
      color: Colors.primaries[i % Colors.primaries.length][400]!,
      borderRadius: BorderRadius.circular(16),
    ),
    alignment: Alignment.center,
    child: Text(
      '${i + 1}',
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    ),
  );
}
