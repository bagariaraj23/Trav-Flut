import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/models/trip.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/providers/final_post_provider.dart';
import 'package:tripthread/services/media_service.dart';
import 'package:tripthread/services/trip_service.dart';
import 'package:tripthread/utils/app_layout.dart';
import 'package:tripthread/utils/app_theme.dart';
import 'package:tripthread/utils/cloudinary_utils.dart';
import 'package:tripthread/screens/post/post_preview_screen.dart';
import 'package:tripthread/widgets/feed/final_post_template_picker.dart';
import 'package:tripthread/widgets/media/media_seek.dart';
import 'package:tripthread/utils/trip_time_format.dart';

class FinalPostEditScreen extends StatefulWidget {
  final String tripId;

  const FinalPostEditScreen({super.key, required this.tripId});

  @override
  State<FinalPostEditScreen> createState() => _FinalPostEditScreenState();
}

class _FinalPostEditScreenState extends State<FinalPostEditScreen> {
  Trip? _trip;
  List<TripThreadEntry> _threadEntries = const [];
  bool _isTripLoading = true;
  String? _tripError;
  final TextEditingController _summaryController = TextEditingController();
  final TextEditingController _captionController = TextEditingController();
  final FocusNode _summaryFocus = FocusNode();
  final FocusNode _captionFocus = FocusNode();
  bool _isSummaryEditing = false;
  bool _isCaptionEditing = false;
  bool _uploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    _loadTripDetails();
    _summaryFocus.addListener(() {
      if (!_summaryFocus.hasFocus && _isSummaryEditing) {
        setState(() => _isSummaryEditing = false);
      }
    });
    _captionFocus.addListener(() {
      if (!_captionFocus.hasFocus && _isCaptionEditing) {
        setState(() => _isCaptionEditing = false);
      }
    });
  }

  Future<void> _loadTripDetails() async {
    final tripService = context.read<TripService>();
    final response = await tripService.getTrip(widget.tripId);

    if (!mounted) return;

    if (response.success && response.data != null) {
      final trip = response.data!;
      final authId = context.read<AuthProvider>().currentUser?.id;
      final isMember = authId != null &&
          (trip.userId == authId ||
              (trip.participants?.any((participant) => participant.userId == authId) ??
                  false));
      final entries = await _loadAllThreadEntries(tripService);
      if (!mounted) return;
      context.read<FinalPostProvider>().setCanEdit(isMember);
      setState(() {
        _trip = trip;
        _threadEntries = entries;
        _isTripLoading = false;
        _tripError = null;
      });
    } else {
      if (mounted) {
        context.read<FinalPostProvider>().setCanEdit(false);
      }
      setState(() {
        _tripError = response.error ?? 'Failed to load trip details';
        _isTripLoading = false;
      });
    }
  }

  Future<void> _refresh(FinalPostProvider provider) async {
    await Future.wait([
      provider.loadDraft(widget.tripId),
      _loadTripDetails(),
    ]);
  }

  void _syncControllers(TripFinalPost? draft) {
    if (draft == null) return;
    _updateController(_summaryController, draft.summaryText);
    _updateController(_captionController, draft.caption ?? '');
  }

  void _updateController(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  Future<List<TripThreadEntry>> _loadAllThreadEntries(TripService tripService) async {
    final collected = <TripThreadEntry>[];
    String? cursor;
    for (var page = 0; page < 20; page++) {
      final response = await tripService.getThreadEntries(
        widget.tripId,
        limit: 50,
        olderThanCursor: cursor,
      );
      if (!response.success || response.data == null) break;
      collected.addAll(response.data!.items);
      final next = response.data!.nextOlderCursor;
      if (!response.data!.hasMoreOlder || next == null || next.isEmpty) break;
      cursor = next;
    }
    return collected;
  }

  List<Media> get _mediaItems {
    final entries = _threadEntries;
    final items = entries
        .map((entry) => entry.media)
        .whereType<Media>()
        .where((media) => media.type == MediaType.image && media.url.isNotEmpty)
        .toList();
    final seen = <String>{};
    return items.where((media) {
      final already = seen.contains(media.url);
      seen.add(media.url);
      return !already;
    }).toList();
  }

  @override
  void dispose() {
    _summaryController.dispose();
    _captionController.dispose();
    _summaryFocus.dispose();
    _captionFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FinalPostProvider>();
    final draft = provider.draft;
    _syncControllers(draft);

    final isBusy = provider.isLoading || draft == null || _isTripLoading;
    final canEditContent = draft != null && provider.canEdit;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/trip/${widget.tripId}');
            }
          },
        ),
        title: const Text('Final Post'),
        actions: [
          if (provider.isSaving)
            const Padding(
              padding: EdgeInsets.only(right: 16.0),
              child: Center(child: Text('Saving...')),
            ),
        ],
      ),
      body: isBusy
          ? const Center(child: CircularProgressIndicator())
          : AppLayout.reading(
              context: context,
              child: RefreshIndicator(
              onRefresh: () => _refresh(provider),
              child: ListView(
                padding: const EdgeInsets.all(16),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (provider.error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        provider.error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (_tripError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _tripError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  _buildPreviewCard(draft),
                  const SizedBox(height: 16),
                  _buildInputField(
                    title: 'Summary',
                    hint: 'Describe your trip highlights and story...',
                    controller: _summaryController,
                    focusNode: _summaryFocus,
                    onChanged: provider.updateSummary,
                    minLines: 5,
                    maxLines: 10,
                    editable: canEditContent,
                    isEditing: _isSummaryEditing,
                    onToggleEdit: () {
                      if (!canEditContent) return;
                      setState(() => _isSummaryEditing = true);
                      Future.microtask(() => _summaryFocus.requestFocus());
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildInputField(
                    title: 'Hashtags',
                    hint: '#Bali #SummerGetaway',
                    controller: _captionController,
                    focusNode: _captionFocus,
                    onChanged: provider.updateCaption,
                    minLines: 2,
                    maxLines: 4,
                    editable: canEditContent,
                    isEditing: _isCaptionEditing,
                    onToggleEdit: () {
                      if (!canEditContent) return;
                      setState(() => _isCaptionEditing = true);
                      Future.microtask(() => _captionFocus.requestFocus());
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildMediaSelector(provider, draft),
                  const SizedBox(height: 16),
                  _buildTripMetadata(),
                  if (!draft.isPublished) ...[
                    const SizedBox(height: 20),
                    FinalPostTemplatePicker(
                      value: draft.templateChoice,
                      enabled: canEditContent,
                      onChanged: provider.setTemplateChoice,
                    ),
                  ],
                  const SizedBox(height: 80),
                ],
              ),
            ),
            ),
      bottomNavigationBar: draft == null
          ? null
          : _buildBottomBar(context, provider, draft),
    );
  }

  Widget _buildPreviewCard(TripFinalPost draft) {
    final coverUrl =
        draft.coverMediaUrl ??
        (draft.curatedMedia.isNotEmpty ? draft.curatedMedia.first : null);
    final tripTitle = _trip?.title ?? 'Your Journey';
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (coverUrl != null)
            AspectRatio(
              aspectRatio: 4 / 3,
              child: Image.network(
                buildOptimizedImageUrl(coverUrl, width: 1200),
                fit: BoxFit.cover,
              ),
            )
          else
            Container(
              height: 180,
              decoration: BoxDecoration(
                gradient: AppTheme.brandWash(Theme.of(context).brightness),
              ),
              child: const Center(
                child: Icon(Icons.photo, color: Colors.white, size: 48),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tripTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  draft.summaryText,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                if (draft.caption != null && draft.caption!.isNotEmpty)
                  Text(
                    draft.caption!,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.9),
                        ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField({
    required String title,
    required String hint,
    required TextEditingController controller,
    required FocusNode focusNode,
    required ValueChanged<String> onChanged,
    required VoidCallback onToggleEdit,
    required bool editable,
    required bool isEditing,
    int? maxLines,
    int minLines = 3,
  }) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          )
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.edit_outlined,
                  color: editable
                      ? (isEditing
                          ? theme.colorScheme.primary
                          : theme.iconTheme.color)
                      : theme.disabledColor,
                ),
                tooltip: editable
                    ? 'Edit $title'
                    : 'Only you can edit your final post',
                onPressed: editable ? onToggleEdit : null,
              )
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            focusNode: focusNode,
            controller: controller,
            onChanged: onChanged,
            minLines: minLines,
            maxLines: maxLines,
            readOnly: !editable || !isEditing,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              hintText: hint,
              filled: true,
              fillColor: theme.colorScheme.surface,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _uploadFromDevice(
    FinalPostProvider provider, {
    required bool fromCamera,
  }) async {
    if (_uploadingPhoto || !provider.canEdit) return;
    try {
      final file = await context.read<MediaService>().pickImage(
            fromCamera: fromCamera,
          );
      if (file == null || !mounted) return;
      setState(() => _uploadingPhoto = true);
      final media = await context.read<MediaService>().uploadMediaToCloudinary(
            file: file,
            tripId: widget.tripId,
            usage: 'final_post',
          );
      if (!mounted) return;
      if (media == null || media.url.isEmpty) {
        throw Exception('The photo did not upload');
      }
      final ok = provider.toggleMedia(media.url);
      if (!ok && provider.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(provider.error!)),
        );
      }
      await _loadTripDetails();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Widget _buildMediaSelector(
      FinalPostProvider provider, TripFinalPost draft) {
    final mediaItems = _mediaItems;
    final locked = !provider.canEdit;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Photos (${draft.curatedMedia.length}/12)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: !locked && draft.curatedMedia.isNotEmpty
                          ? () => provider.setCoverMedia(
                                draft.curatedMedia.first,
                              )
                          : null,
                      child: const Text('Use first as cover'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                locked
                    ? 'Only you can change the photos on your final post.'
                    : 'Pick photos already on this trip, or add one from your phone. A photo has to be yours, or already on the trip.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).hintColor),
              ),
            ),
            if (!locked)
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _uploadingPhoto
                        ? null
                        : () => _uploadFromDevice(provider, fromCamera: false),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Phone'),
                  ),
                  TextButton.icon(
                    onPressed: _uploadingPhoto
                        ? null
                        : () => _uploadFromDevice(provider, fromCamera: true),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Camera'),
                  ),
                  if (_uploadingPhoto)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            if (mediaItems.isEmpty)
              const Text('Photos from this trip show up here.')
            else
              SizedBox(
                height: 110,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: mediaItems.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final media = mediaItems[index];
                    final url = media.url;
                    final isSelected = draft.curatedMedia.contains(url);
                    final isCover = draft.coverMediaUrl == url;
                    final order = draft.curatedMedia.indexOf(url);
                    return GestureDetector(
                      onTap: locked
                          ? null
                          : () {
                              final ok = provider.toggleMedia(url);
                              if (!ok &&
                                  provider.error != null &&
                                  context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(provider.error!)),
                                );
                              }
                            },
                      onLongPress:
                          locked ? null : () => _handleSetCover(provider, url),
                      child: Stack(
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
                          if (isSelected && order >= 0)
                            Positioned(
                              top: 8,
                              left: 8,
                              child: PhotoOrderBadge(position: order + 1),
                            ),
                          if (isSelected)
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black45,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.check_circle,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          if (isCover)
                            Positioned(
                              bottom: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black87.withValues(alpha: 0.7),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'Cover',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _handleSetCover(FinalPostProvider provider, String url) {
    provider.setCoverMedia(url);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cover photo updated')),
    );
  }

  Widget _buildTripMetadata() {
    if (_trip == null) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Trip Details',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _MetadataChip(
                  icon: Icons.calendar_month,
                  label:
                      formatTripRange(
                        _trip!.startDate,
                        _trip!.endDate,
                        scheduleTimezone: _trip!.scheduleTimezone,
                      ),
                ),
                if (_trip!.destinations.isNotEmpty)
                  _MetadataChip(
                    icon: Icons.location_on,
                    label: _trip!.destinations.join(', '),
                  ),
                _MetadataChip(
                  icon: Icons.people,
                  label: '${_trip!.participantCount} participants',
                ),
                _MetadataChip(
                  icon: Icons.note_alt,
                  label: '${_trip!.entryCount} entries',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteDraft(FinalPostProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this draft?'),
        content: const Text(
          'This removes your unpublished final post. The trip and everyone else’s posts stay.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final success = await provider.deleteFinalPost();
    if (!mounted) return;
    if (!success) {
      messenger.showSnackBar(
        SnackBar(content: Text(provider.error ?? 'Could not delete the draft')),
      );
      return;
    }
    messenger.showSnackBar(const SnackBar(content: Text('Draft deleted')));
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/trip/${widget.tripId}');
    }
  }

  Widget _buildBottomBar(
      BuildContext context, FinalPostProvider provider, TripFinalPost draft) {
    if (draft.isPublished) {
      if (!provider.canEdit) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: () => context.push('/post/TRIP_FINAL_POST/${draft.id}'),
              icon: const Icon(Icons.visibility),
              label: const Text('View post'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ),
        );
      }
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: provider.isSaving
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final success = await provider.saveDraft();
                          if (!mounted) return;
                          if (success) {
                            messenger.showSnackBar(
                              const SnackBar(content: Text('Changes saved')),
                            );
                          }
                        },
                  child: provider.isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save changes'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () =>
                      context.push('/post/TRIP_FINAL_POST/${draft.id}'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text('View post'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: provider.isSaving
                        ? null
                        : () async {
                            final messenger = ScaffoldMessenger.of(context);
                            final success = await provider.saveDraft();
                            if (!mounted) return;
                            if (success) {
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text('Draft saved'),
                                ),
                              );
                            }
                          },
                    child: provider.isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save Draft'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: provider.isPublishing || provider.isSaving
                        ? null
                        : () async {
                            final messenger = ScaffoldMessenger.of(context);
                            final router = GoRouter.of(context);
                            // Persist latest edits so preview matches the draft.
                            final saved = await provider.saveDraft();
                            if (!mounted) return;
                            if (!saved) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    provider.error ?? 'Could not save draft',
                                  ),
                                ),
                              );
                              return;
                            }
                            // Reload so thread/map preview fields are present.
                            await provider.loadDraft(widget.tripId);
                            if (!mounted) return;
                            final preview = provider.draft;
                            if (preview == null) return;
                            final result =
                                await Navigator.of(context).push<Map<String, dynamic>>(
                              MaterialPageRoute(
                                builder: (context) => PostPreviewScreen(
                                  post: preview,
                                  title: 'Trip post preview',
                                  onSaveDraft: () => provider.saveDraft(),
                                  onPublish: () => provider.publish(),
                                ),
                              ),
                            );
                            if (!mounted || result == null) return;
                            if (result['published'] == true) {
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text('Trip published to your feed!'),
                                ),
                              );
                              router.go('/home');
                            } else if (result['saved'] == true) {
                              messenger.showSnackBar(
                                const SnackBar(content: Text('Draft saved')),
                              );
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: provider.isPublishing || provider.isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Preview'),
                  ),
                ),
              ],
            ),
            TextButton(
              onPressed: provider.isSaving || provider.isPublishing
                  ? null
                  : () => _confirmDeleteDraft(provider),
              child: const Text('Delete draft'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetadataChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetadataChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

