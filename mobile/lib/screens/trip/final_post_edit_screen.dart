import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/models/trip.dart';
import 'package:tripthread/providers/final_post_provider.dart';
import 'package:tripthread/services/trip_service.dart';
import 'package:tripthread/utils/cloudinary_utils.dart';

class FinalPostEditScreen extends StatefulWidget {
  final String tripId;

  const FinalPostEditScreen({super.key, required this.tripId});

  @override
  State<FinalPostEditScreen> createState() => _FinalPostEditScreenState();
}

class _FinalPostEditScreenState extends State<FinalPostEditScreen> {
  Trip? _trip;
  bool _isTripLoading = true;
  String? _tripError;
  final TextEditingController _summaryController = TextEditingController();
  final TextEditingController _captionController = TextEditingController();
  final FocusNode _summaryFocus = FocusNode();
  final FocusNode _captionFocus = FocusNode();
  bool _isSummaryEditing = false;
  bool _isCaptionEditing = false;

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
      setState(() {
        _trip = response.data;
        _isTripLoading = false;
        _tripError = null;
      });
    } else {
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

  List<Media> get _mediaItems {
    final entries = _trip?.threadEntries ?? [];
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
    final isEditableDraft = draft != null && !draft.isPublished;

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
          : RefreshIndicator(
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
                    editable: isEditableDraft,
                    isEditing: _isSummaryEditing,
                    onToggleEdit: () {
                      if (!isEditableDraft) return;
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
                    editable: isEditableDraft,
                    isEditing: _isCaptionEditing,
                    onToggleEdit: () {
                      if (!isEditableDraft) return;
                      setState(() => _isCaptionEditing = true);
                      Future.microtask(() => _captionFocus.requestFocus());
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildMediaSelector(provider, draft),
                  const SizedBox(height: 16),
                  _buildTripMetadata(),
                  const SizedBox(height: 80),
                ],
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
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primary,
                    Theme.of(context).colorScheme.secondary,
                  ],
                ),
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
                        ?.copyWith(color: Colors.grey[700]),
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
                    : 'Editing disabled after publish',
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

  Widget _buildMediaSelector(
      FinalPostProvider provider, TripFinalPost draft) {
    final mediaItems = _mediaItems;
    final locked = draft.isPublished;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Photos (${draft.curatedMedia.length}/10)',
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
            if (locked)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Photos are locked after publishing.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).hintColor),
                ),
              ),
            if (mediaItems.isEmpty)
              const Text(
                  'Add photos to your trip thread to curate them here.')
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
                    return GestureDetector(
                      onTap:
                          locked ? null : () => provider.toggleMedia(url),
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
                      '${_trip!.startDate.toLocal().toShortDateString()} - ${_trip!.endDate.toLocal().toShortDateString()}',
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

  Widget _buildBottomBar(
      BuildContext context, FinalPostProvider provider, TripFinalPost draft) {
    if (draft.isPublished) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            onPressed: () => context.go('/home'),
            icon: const Icon(Icons.check_circle),
            label: const Text('View Published Post'),
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
                onPressed: provider.isPublishing
                    ? null
                    : () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final navigator = context;
                        final success = await provider.publish();
                        if (!mounted) return;
                        if (success) {
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('Trip published to your feed!'),
                            ),
                          );
                          navigator.go('/home');
                        }
                      },
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: provider.isPublishing
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Publish'),
              ),
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

extension _DateFormatting on DateTime {
  String toShortDateString() {
    return '${day.toString().padLeft(2, '0')}/'
        '${month.toString().padLeft(2, '0')}/'
        '${year.toString()}';
  }
}

