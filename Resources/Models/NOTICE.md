# WholeBodyPose.mlpackage

Whole-body pose (133 keypoints: body, feet, face, hands) for one person in a 192x256 crop.

- Model: DWPose RTMPose-m (`rtmpose-m_simcc-ucoco_dw-ucoco_270e-256x192-c8b76419_20230728`), from
  OpenMMLab MMPose, https://github.com/open-mmlab/mmpose, released under the Apache License 2.0
  (`LICENSE-Apache-2.0.txt`).
- Changed for Edit Assist: converted from the ONNX release to Core ML (float16), with the input
  normalisation and the SimCC decoding (peak position and score per keypoint) built in. Input `rgb`
  (1x3x256x192, values 0-255); output `points` (1x133x3: x in 0..192, y in 0..256, score).
- Run it on the GPU (`.cpuAndGPU`): on the Neural Engine and the CPU, float16 loses some keypoint scores.
