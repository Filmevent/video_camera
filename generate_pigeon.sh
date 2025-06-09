#!/bin/bash
dart run pigeon \
  --input pigeons/camera_api.dart \
  --dart_out lib/src/generated/camera_api.g.dart \
  --swift_out ios/Classes/CameraApi.swift \

echo "Pigeon code generation complete!"