import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tripthread/utils/cloudinary_utils.dart';
import 'package:tripthread/utils/locale_dates.dart';
import 'package:tripthread/widgets/media/app_video.dart';
import 'package:tripthread/widgets/media/media_seek.dart';

class GalleryMedia {
  final String id;
  final String url;
  final bool isVideo;
  final DateTime sharedAt;

  const GalleryMedia({
    required this.id,
    required this.url,
    required this.isVideo,
    required this.sharedAt,
  });
}

class MediaGalleryViewer extends StatefulWidget {
  const MediaGalleryViewer({
    super.key,
    required this.items,
    required this.initialIndex,
    this.onNearEnd,
  });

  final List<GalleryMedia> items;
  final int initialIndex;
  final Future<void> Function()? onNearEnd;

  @override
  State<MediaGalleryViewer> createState() => _MediaGalleryViewerState();
}

class _MediaGalleryViewerState extends State<MediaGalleryViewer> {
  late final PageController _pageController;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.items.length - 1);
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPage(int index) {
    setState(() => _index = index);
    if (widget.onNearEnd != null && index >= widget.items.length - 3) {
      widget.onNearEnd!();
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.items[_index];
    final stamp = LocaleDates.mediumDateTime(item.sharedAt.toLocal());
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: widget.items.length,
              onPageChanged: _onPage,
              itemBuilder: (context, index) {
                final media = widget.items[index];
                if (media.isVideo) {
                  return _GalleryVideoPage(
                    url: media.url,
                    active: index == _index,
                  );
                }
                return InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4,
                  child: Center(
                    child: Image.network(
                      buildOptimizedImageUrl(media.url, width: 1600),
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white70,
                        size: 64,
                      ),
                    ),
                  ),
                );
              },
            ),
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                    style: IconButton.styleFrom(backgroundColor: Colors.black45),
                  ),
                  const Spacer(),
                  Text(
                    stamp,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GalleryVideoPage extends StatefulWidget {
  const _GalleryVideoPage({required this.url, required this.active});

  final String url;
  final bool active;

  @override
  State<_GalleryVideoPage> createState() => _GalleryVideoPageState();
}

class _GalleryVideoPageState extends State<_GalleryVideoPage> {
  AppVideoController? _controller;
  Timer? _ticker;
  bool _ready = false;
  bool _playing = false;
  bool _looping = true;
  double _speed = 1;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _error;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void didUpdateWidget(covariant _GalleryVideoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active && oldWidget.active) {
      _controller?.pause();
      if (mounted) setState(() => _playing = false);
    }
  }

  Future<void> _open() async {
    try {
      final videoUrl = widget.url.contains('/upload/')
          ? buildOptimizedVideoUrl(widget.url, maxWidth: 1920)
          : widget.url;
      final controller = AppVideoController.networkUrl(Uri.parse(videoUrl));
      _controller = controller;
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      controller.setLooping(true);
      if (widget.active) {
        await controller.play();
        _playing = true;
      }
      setState(() {
        _ready = true;
        _duration = controller.duration;
      });
      _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
        final current = _controller;
        if (!mounted || current == null || !current.isInitialized) return;
        setState(() {
          _position = current.position;
          _duration = current.duration;
          _playing = current.isPlaying;
        });
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Failed to load video.');
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _seekBy(Duration delta) async {
    final controller = _controller;
    if (controller == null) return;
    final next = clampSeek(controller.position, delta, controller.duration);
    await controller.seekTo(next);
    if (mounted) setState(() => _position = next);
  }

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller == null) return;
    if (controller.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
    if (mounted) setState(() => _playing = controller.isPlaying);
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Text(_error!, style: const TextStyle(color: Colors.white70)),
      );
    }
    if (!_ready || _controller == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    final controller = _controller!;
    return Column(
      children: [
        Expanded(
          child: GallerySkipLayer(
            onSkip: _seekBy,
            child: GestureDetector(
              onTap: _togglePlay,
              child: Center(
                child: AspectRatio(
                  aspectRatio: controller.aspectRatio,
                  child: controller.buildView(),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            children: [
              Slider(
                value: _duration.inMilliseconds == 0
                    ? 0
                    : (_position.inMilliseconds / _duration.inMilliseconds)
                        .clamp(0, 1)
                        .toDouble(),
                onChanged: (value) async {
                  final target = Duration(
                    milliseconds: (_duration.inMilliseconds * value).round(),
                  );
                  await controller.seekTo(target);
                  if (mounted) setState(() => _position = target);
                },
              ),
              Row(
                children: [
                  IconButton(
                    onPressed: _togglePlay,
                    icon: Icon(
                      _playing ? Icons.pause_circle : Icons.play_circle,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Rewind',
                    onPressed: () async {
                      await controller.seekTo(Duration.zero);
                      if (mounted) setState(() => _position = Duration.zero);
                    },
                    icon: const Icon(Icons.replay, color: Colors.white),
                  ),
                  IconButton(
                    tooltip: _looping ? 'Loop on' : 'Loop off',
                    onPressed: () {
                      setState(() => _looping = !_looping);
                      controller.setLooping(_looping);
                    },
                    icon: Icon(
                      Icons.loop,
                      color: _looping ? Colors.white : Colors.white38,
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final speed = nextPlaybackSpeed(_speed);
                      await controller.setPlaybackSpeed(speed);
                      if (mounted) setState(() => _speed = speed);
                    },
                    child: Text(
                      '${_speed}x',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
