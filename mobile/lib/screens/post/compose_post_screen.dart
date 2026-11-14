import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/models/trip.dart';
import 'package:tripthread/services/api_service.dart';
import 'package:tripthread/services/media_service.dart';
import 'package:tripthread/utils/cloudinary_utils.dart';

/// A post that is not attached to a trip: caption, phone photos, optional place.
class ComposePostScreen extends StatefulWidget {
  final String? postId;

  const ComposePostScreen({super.key, this.postId});

  @override
  State<ComposePostScreen> createState() => _ComposePostScreenState();
}

class _ComposePostScreenState extends State<ComposePostScreen> {
  final TextEditingController _caption = TextEditingController();
  final TextEditingController _location = TextEditingController();
  final List<String> _media = [];
  bool _loading = false;
  bool _uploading = false;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.postId != null;

  @override
  void initState() {
    super.initState();
    if (_editing) _load();
  }

  @override
  void dispose() {
    _caption.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final response = await context.read<ApiService>().getPost(
          'USER_POST',
          widget.postId!,
        );
    if (!mounted) return;
    if (!response.success || response.data == null) {
      setState(() {
        _loading = false;
        _error = response.error ?? 'Could not open that post';
      });
      return;
    }
    final post = TripFinalPost.fromJson(response.data!);
    _caption.text = post.summaryText;
    _location.text = post.locationName ?? '';
    _media
      ..clear()
      ..addAll(post.curatedMedia);
    setState(() => _loading = false);
  }

  Future<void> _addPhoto({required bool fromCamera}) async {
    if (_uploading || _media.length >= 12) return;
    try {
      final file = await context.read<MediaService>().pickImage(
            fromCamera: fromCamera,
          );
      if (file == null || !mounted) return;
      setState(() => _uploading = true);
      final media = await context.read<MediaService>().uploadMediaToCloudinary(
            file: file,
            usage: 'user_post',
          );
      if (!mounted) return;
      if (media == null || media.url.isEmpty) {
        throw Exception('The photo did not upload');
      }
      if (!_media.contains(media.url)) {
        setState(() => _media.add(media.url));
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    final caption = _caption.text.trim();
    if (caption.isEmpty) {
      setState(() => _error = 'Write a caption before posting');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final api = context.read<ApiService>();
    final location = _location.text.trim();
    final response = _editing
        ? await api.updateDirectPost(
            widget.postId!,
            caption: caption,
            media: List<String>.from(_media),
            locationName: location.isEmpty ? null : location,
          )
        : await api.createDirectPost(
            caption: caption,
            media: List<String>.from(_media),
            locationName: location.isEmpty ? null : location,
          );
    if (!mounted) return;
    setState(() => _saving = false);
    if (response.success) {
      context.pop(true);
      return;
    }
    setState(() => _error = response.error ?? 'Could not publish the post');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Edit post' : 'New post'),
        actions: [
          TextButton(
            onPressed: _saving || _loading ? null : _save,
            child: Text(_editing ? 'Save' : 'Post'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _caption,
                  minLines: 4,
                  maxLines: 8,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    hintText: 'Write a caption',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _location,
                  decoration: const InputDecoration(
                    hintText: 'Location, if you want one',
                    prefixIcon: Icon(Icons.place_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: _uploading || _media.length >= 12
                          ? null
                          : () => _addPhoto(fromCamera: false),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Phone'),
                    ),
                    TextButton.icon(
                      onPressed: _uploading || _media.length >= 12
                          ? null
                          : () => _addPhoto(fromCamera: true),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Camera'),
                    ),
                    if (_uploading)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                Text(
                  '${_media.length}/12 photos',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                if (_media.isNotEmpty)
                  SizedBox(
                    height: 110,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _media.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final url = _media[index];
                        return Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                buildOptimizedImageUrl(url, width: 400),
                                width: 110,
                                height: 110,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: IconButton(
                                onPressed: () =>
                                    setState(() => _media.removeAt(index)),
                                icon: const Icon(Icons.close, size: 18),
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.black54,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
    );
  }
}
