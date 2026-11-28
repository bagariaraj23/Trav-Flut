import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/models/place.dart';
import 'package:tripthread/models/trip.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/screens/post/post_preview_screen.dart';
import 'package:tripthread/services/api_service.dart';
import 'package:tripthread/services/media_service.dart';
import 'package:tripthread/utils/cloudinary_utils.dart';
import 'package:tripthread/widgets/sheets/map_picker_sheet_mobile.dart';

/// A post that is not attached to a trip: caption, phone photos, optional place.
/// Layout is always postcard on the home feed.
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
  double? _latitude;
  double? _longitude;
  String? _placeId;
  String? _draftId;
  bool _loading = false;
  bool _uploading = false;
  bool _saving = false;
  String? _error;

  bool get _editing => (_draftId ?? widget.postId) != null;
  String? get _postId => _draftId ?? widget.postId;

  @override
  void initState() {
    super.initState();
    _draftId = widget.postId;
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
          _postId!,
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
    _latitude = post.latitude;
    _longitude = post.longitude;
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

  Future<void> _pickOnMap() async {
    final place = await Navigator.of(context).push<Place>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => MapPickerModal(
          initialPlaceName: _location.text.trim().isEmpty
              ? null
              : _location.text.trim(),
          initialLat: _latitude,
          initialLng: _longitude,
        ),
      ),
    );
    if (place == null || !mounted) return;
    setState(() {
      _location.text = place.name;
      _latitude = place.lat;
      _longitude = place.lng;
      _placeId = place.id;
    });
  }

  void _clearLocation() {
    setState(() {
      _location.clear();
      _latitude = null;
      _longitude = null;
      _placeId = null;
    });
  }

  TripFinalPost _buildPreviewPost() {
    final caption = _caption.text.trim();
    final location = _location.text.trim();
    final user = context.read<AuthProvider>().currentUser;
    final now = DateTime.now().toUtc();
    final pins = (_latitude != null && _longitude != null)
        ? [
            FeedMapPin(
              lat: _latitude!,
              lng: _longitude!,
              name: location.isEmpty ? null : location,
            ),
          ]
        : null;
    return TripFinalPost(
      id: _postId ?? 'preview-direct',
      tripId: null,
      userId: user?.id,
      summaryText: caption,
      curatedMedia: List<String>.from(_media),
      caption: caption,
      coverMediaUrl: _media.isNotEmpty ? _media.first : null,
      postKind: 'direct',
      locationName: location.isEmpty ? null : location,
      latitude: _latitude,
      longitude: _longitude,
      templateChoice: FinalPostTemplateChoice.postcard,
      generationStatus: GenerationStatus.draft,
      isPublished: false,
      publishedAt: null,
      createdAt: now,
      updatedAt: now,
      user: user,
      mapPins: pins,
    );
  }

  Future<bool> _persist({required bool publish}) async {
    final caption = _caption.text.trim();
    if (caption.isEmpty) {
      setState(() => _error = 'Write a caption before continuing');
      return false;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final api = context.read<ApiService>();
    final location = _location.text.trim();
    final existingId = _postId;
    final response = existingId != null
        ? await api.updateDirectPost(
            existingId,
            caption: caption,
            media: List<String>.from(_media),
            locationName: location.isEmpty ? null : location,
            latitude: _latitude,
            longitude: _longitude,
            placeId: _placeId,
            isPublished: publish,
          )
        : await api.createDirectPost(
            caption: caption,
            media: List<String>.from(_media),
            locationName: location.isEmpty ? null : location,
            latitude: _latitude,
            longitude: _longitude,
            placeId: _placeId,
            isPublished: publish,
          );
    if (!mounted) return false;
    setState(() => _saving = false);
    if (!response.success) {
      setState(() => _error = response.error ?? 'Could not save the post');
      return false;
    }
    if (existingId == null && response.data != null) {
      final created = TripFinalPost.fromJson(response.data!);
      if (created.id.isNotEmpty) {
        setState(() => _draftId = created.id);
      }
    }
    return true;
  }

  Future<void> _openPreview() async {
    final caption = _caption.text.trim();
    if (caption.isEmpty) {
      setState(() => _error = 'Write a caption before previewing');
      return;
    }
    setState(() => _error = null);
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (context) => PostPreviewScreen(
          post: _buildPreviewPost(),
          title: 'Post preview',
          onSaveDraft: () => _persist(publish: false),
          onPublish: () => _persist(publish: true),
        ),
      ),
    );
    if (!mounted || result == null) return;
    if (result['published'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Post published to your feed')),
      );
      context.go('/home');
      return;
    }
    if (result['saved'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Draft saved')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasCoords = _latitude != null && _longitude != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Edit post' : 'New post'),
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
                  decoration: InputDecoration(
                    hintText: 'Location, if you want one',
                    prefixIcon: const Icon(Icons.place_outlined),
                    border: const OutlineInputBorder(),
                    suffixIcon: _location.text.isNotEmpty || hasCoords
                        ? IconButton(
                            tooltip: 'Clear location',
                            onPressed: _clearLocation,
                            icon: const Icon(Icons.clear),
                          )
                        : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _pickOnMap,
                  icon: const Icon(Icons.map_outlined),
                  label: Text(
                    hasCoords ? 'Change place on map' : 'Pick place on map',
                  ),
                ),
                if (hasCoords)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Map pin set — postcard preview will show a Mapbox thumb.',
                      style: Theme.of(context).textTheme.bodySmall,
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
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: ElevatedButton(
            onPressed: _saving || _loading ? null : _openPreview,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Preview'),
          ),
        ),
      ),
    );
  }
}
