#!/usr/bin/env bash
# Download the OpenCV YuNet (detect) + SFace (recognize) ONNX models.
# Tiny (~2 MB + ~37 MB); cv2 >= 4.7 loads them via FaceDetectorYN / FaceRecognizerSF.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)/models"
mkdir -p "$DIR"
BASE="https://github.com/opencv/opencv_zoo/raw/main/models"
declare -A M=(
  ["face_detection_yunet_2023mar.onnx"]="$BASE/face_detection_yunet/face_detection_yunet_2023mar.onnx"
  ["face_recognition_sface_2021dec.onnx"]="$BASE/face_recognition_sface/face_recognition_sface_2021dec.onnx"
)
for f in "${!M[@]}"; do
  if [ -s "$DIR/$f" ]; then echo "have $f"; continue; fi
  echo "fetching $f ..."
  curl -sSL --fail -o "$DIR/$f" "${M[$f]}"
done
ls -la "$DIR"
