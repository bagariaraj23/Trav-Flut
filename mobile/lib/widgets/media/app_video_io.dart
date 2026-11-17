import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Mobile video playback. Same calls the thread screen used with video_player.
class AppVideoController {
  AppVideoController.networkUrl(Uri url)
    : _controller = VideoPlayerController.networkUrl(url);

  AppVideoController.file(String path)
    : _controller = VideoPlayerController.file(File(path));

  final VideoPlayerController _controller;

  Future<void> initialize() => _controller.initialize();

  void dispose() => _controller.dispose();

  void setLooping(bool value) => _controller.setLooping(value);

  void setVolume(double value) => _controller.setVolume(value);

  Future<void> play() => _controller.play();

  Future<void> pause() => _controller.pause();

  Duration get position => _controller.value.position;

  Future<void> seekTo(Duration position) => _controller.seekTo(position);

  Future<void> setPlaybackSpeed(double speed) =>
      _controller.setPlaybackSpeed(speed);

  bool get isInitialized => _controller.value.isInitialized;

  bool get isPlaying => _controller.value.isPlaying;

  Duration get duration => _controller.value.duration;

  double get aspectRatio {
    final ratio = _controller.value.aspectRatio;
    if (ratio.isNaN || ratio <= 0) return 16 / 9;
    return ratio;
  }

  Size get size => _controller.value.size;

  Widget buildView() => VideoPlayer(_controller);
}
