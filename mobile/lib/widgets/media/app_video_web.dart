import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

/// Browser playback for the Docker web UI.
///
/// video_player imports dart:io, so the web build cannot use that library.
/// Network and blob URLs both play through an HTML video element.
class AppVideoController {
  AppVideoController.networkUrl(Uri url) : _source = url.toString();

  AppVideoController.file(String path) : _source = path;

  final String _source;
  html.VideoElement? _video;
  String? _viewType;
  bool _initialized = false;

  Future<void> initialize() async {
    final video = html.VideoElement()
      ..src = _source
      ..autoplay = false
      ..controls = false
      ..preload = 'auto';
    video.setAttribute('playsinline', 'true');
    _video = video;
    _viewType = 'tripthread-video-${identityHashCode(this)}';
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType!,
      (int viewId) => video,
    );

    if (video.readyState >= 1) {
      _initialized = true;
      return;
    }

    final loaded = Completer<void>();
    late StreamSubscription<html.Event> metadataSub;
    late StreamSubscription<html.Event> errorSub;
    metadataSub = video.onLoadedMetadata.listen((_) {
      if (!loaded.isCompleted) loaded.complete();
    });
    errorSub = video.onError.listen((_) {
      if (!loaded.isCompleted) {
        loaded.completeError(StateError('Failed to load video'));
      }
    });
    try {
      await loaded.future.timeout(const Duration(seconds: 20));
      _initialized = true;
    } finally {
      await metadataSub.cancel();
      await errorSub.cancel();
    }
  }

  void dispose() {
    final video = _video;
    if (video == null) return;
    video.pause();
    video.src = '';
    video.load();
    _video = null;
  }

  void setLooping(bool value) {
    _video?.loop = value;
  }

  void setVolume(double value) {
    final video = _video;
    if (video == null) return;
    video.volume = value.clamp(0, 1).toDouble();
    video.muted = value == 0;
  }

  Future<void> play() async {
    try {
      await _video?.play();
    } catch (_) {
      // Autoplay can be blocked until the user taps play.
    }
  }

  Future<void> pause() async {
    _video?.pause();
  }

  Duration get position {
    final seconds = _video?.currentTime;
    if (seconds == null || seconds.isNaN || seconds.isInfinite) {
      return Duration.zero;
    }
    return Duration(milliseconds: (seconds * 1000).round());
  }

  Future<void> seekTo(Duration position) async {
    final video = _video;
    if (video == null) return;
    video.currentTime = position.inMilliseconds / 1000;
  }

  Future<void> setPlaybackSpeed(double speed) async {
    final video = _video;
    if (video == null) return;
    video.playbackRate = speed;
  }

  bool get isInitialized => _initialized;

  bool get isPlaying => _video != null && !_video!.paused && !_video!.ended;

  Duration get duration {
    final seconds = _video?.duration;
    if (seconds == null || seconds.isNaN || seconds.isInfinite) {
      return Duration.zero;
    }
    return Duration(milliseconds: (seconds * 1000).round());
  }

  double get aspectRatio {
    final size = this.size;
    if (size.height == 0) return 16 / 9;
    return size.width / size.height;
  }

  Size get size {
    final width = _video?.videoWidth ?? 0;
    final height = _video?.videoHeight ?? 0;
    if (width == 0 || height == 0) return const Size(16, 9);
    return Size(width.toDouble(), height.toDouble());
  }

  Widget buildView() {
    final viewType = _viewType;
    if (viewType == null) return const SizedBox.shrink();
    return HtmlElementView(viewType: viewType);
  }
}
