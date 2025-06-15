import 'package:flutter/material.dart';
import 'package:native_device_orientation/native_device_orientation.dart';

class ManualOrientationController extends StatelessWidget {
  final Widget child;
  final double rotationAngle; // -90, 0, 90, or 180

  const ManualOrientationController({
    Key? key,
    required this.child,
    this.rotationAngle = 90,
  }) : assert(
         rotationAngle == -90 ||
             rotationAngle == 0 ||
             rotationAngle == 90 ||
             rotationAngle == 180,
         'Rotation angle must be -90, 0, 90, or 180',
       ),
       super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mediaQuery = MediaQuery.of(context);

        // Calculate the rotated dimensions
        final isRotated = rotationAngle == 90 || rotationAngle == -90;
        final rotatedWidth =
            isRotated ? constraints.maxHeight : constraints.maxWidth;
        final rotatedHeight =
            isRotated ? constraints.maxWidth : constraints.maxHeight;

        // Calculate rotated padding/safe areas
        final rotatedPadding = _rotateEdgeInsets(
          mediaQuery.padding,
          rotationAngle,
        );
        final rotatedViewPadding = _rotateEdgeInsets(
          mediaQuery.viewPadding,
          rotationAngle,
        );
        final rotatedViewInsets = _rotateEdgeInsets(
          mediaQuery.viewInsets,
          rotationAngle,
        );

        return RotatedBox(
          quarterTurns: (rotationAngle ~/ 90),
          child: MediaQuery(
            // Override MediaQuery with rotated values
            data: mediaQuery.copyWith(
              size: Size(rotatedWidth, rotatedHeight),
              padding: rotatedPadding,
              viewPadding: rotatedViewPadding,
              viewInsets: rotatedViewInsets,
            ),
            child: SizedBox(
              width: rotatedWidth,
              height: rotatedHeight,
              child: child,
            ),
          ),
        );
      },
    );
  }

  EdgeInsets _rotateEdgeInsets(EdgeInsets original, double angle) {
    switch (angle.toInt()) {
      case 90:
        return EdgeInsets.only(
          left: original.bottom,
          top: original.left,
          right: original.top,
          bottom: original.right,
        );
      case -90:
        return EdgeInsets.only(
          left: original.top,
          top: original.right,
          right: original.bottom,
          bottom: original.left,
        );
      case 180:
        return EdgeInsets.only(
          left: original.right,
          top: original.bottom,
          right: original.left,
          bottom: original.top,
        );
      default:
        return original;
    }
  }
}
