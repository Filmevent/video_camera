#!/bin/bash
dart run pigeon \
  --input pigeon/camera_api.dart \
  --dart_out lib/src/generated/camera_api.g.dart \
  --swift_out ios/Classes/CameraApi.swift \


dart run pigeon \
  --input pigeon/camera_api.dart \
  --dart_out lib/src/generated/camera_api.g.dart \
  --objc_header_out ios/Classes/camera_api.h \
  --objc_source_out ios/Classes/camera_api.m \
  --swift_out ios/Classes/camera_api.swift

echo "Pigeon code generation complete!"