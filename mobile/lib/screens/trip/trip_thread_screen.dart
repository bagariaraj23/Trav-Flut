import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/providers/trip_provider.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/providers/engagement_provider.dart';
import 'package:tripthread/models/trip.dart';
import 'package:tripthread/models/user.dart';
import 'package:tripthread/models/place.dart';
import 'package:tripthread/widgets/sheets/map_picker_sheet.dart';
import 'package:tripthread/widgets/sheets/place_search_sheet.dart';
import 'package:tripthread/services/media_service.dart';
import 'package:tripthread/services/api_service.dart';
import 'package:tripthread/utils/cloudinary_utils.dart';
import 'package:tripthread/widgets/floating_trip_nav_button.dart';
import 'package:tripthread/screens/trip/trip_money_pane.dart';
import 'package:tripthread/utils/app_layout.dart';
import 'package:tripthread/utils/app_theme.dart';
import 'package:tripthread/widgets/thread/thread_entry_card.dart';
import 'dart:io';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

class TripThreadScreen extends StatefulWidget {
  final String tripId;
  final String? highlightEntryId;
  final bool openMoneyPane;

  const TripThreadScreen({
    super.key,
    required this.tripId,
    this.highlightEntryId,
    this.openMoneyPane = false,
  });

  @override
  State<TripThreadScreen> createState() => _TripThreadScreenState();
}

class _TripThreadScreenState extends State<TripThreadScreen>
    with TickerProviderStateMixin {
  final _textController = TextEditingController();
  final FocusNode _entryInputFocusNode = FocusNode();
  final _locationController = TextEditingController();
  final _scrollController = ScrollController();
  final _placeSearchScrollController = ScrollController();

  Trip? _trip;
  bool _isLoading = true;
  bool _isLoadingEntries = false;
  ThreadEntryType _selectedType = ThreadEntryType.text;
  MediaService? _mediaService;
  Media? _selectedMediaForEntry;
  bool _isUploadingMedia = false;
  List<Media> _pendingMediaBatch = [];
  double? _uploadProgress;
  Place? _selectedPlace;
  VideoPlayerController? _pendingVideoController;
  bool _pendingVideoInitialized = false;
  bool _isSubmitting = false;
  TripThreadEntry? _replyingToEntry;
  late final AnimationController _replyBannerController;
  late final Animation<double> _replyBannerFadeAnimation;
  late final Animation<double> _replyBannerScaleAnimation;

  // Mention/tagging state
  List<TripParticipant> _tripParticipants = [];
  String? _mentionQuery;
  int? _mentionStartPosition;
  final GlobalKey _textFieldKey = GlobalKey();
  final GlobalKey _stackKey = GlobalKey();

  final Map<String, GlobalKey> _highlightEntryKeys = {};
  bool _pendingOlderPageLoad = false;
  late final PageController _paneController;
  bool _moneyPaneSelected = false;
  bool _composerOpen = false;

  @override
  void initState() {
    super.initState();
    _paneController = PageController(initialPage: widget.openMoneyPane ? 1 : 0);
    _moneyPaneSelected = widget.openMoneyPane;
    _replyBannerController = AnimationController(
      duration: const Duration(milliseconds: 220),
      vsync: this,
    );
    _replyBannerFadeAnimation = CurvedAnimation(
      parent: _replyBannerController,
      curve: Curves.easeOutCubic,
    );
    _replyBannerScaleAnimation = Tween<double>(begin: 0.97, end: 1.0).animate(
      CurvedAnimation(
        parent: _replyBannerController,
        curve: Curves.easeOutBack,
      ),
    );
    _textController.addListener(_onTextChanged);
    _scrollController.addListener(_onThreadScrollNearTop);
    _entryInputFocusNode.addListener(_onComposerFocusChanged);

    // Defer _loadTrip and _loadTripParticipants - they call clearCurrentTripEntries
    // and setState which trigger notifyListeners during build if run in initState
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadTrip();
      _loadTripParticipants();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _mediaService ??= context.read<MediaService>();
  }

  void _onComposerFocusChanged() {
    if (!_entryInputFocusNode.hasFocus || !mounted) return;
    void scrollThreadToEnd() {
      if (!mounted || !_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      if (max > 0) _scrollController.jumpTo(max);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scrollThreadToEnd();
      // Keyboard animates in after focus; scroll again once inset is applied.
      Future.delayed(const Duration(milliseconds: 280), scrollThreadToEnd);
    });
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _entryInputFocusNode.removeListener(_onComposerFocusChanged);
    _textController.dispose();
    _entryInputFocusNode.dispose();
    _locationController.dispose();
    _scrollController.removeListener(_onThreadScrollNearTop);
    _scrollController.dispose();
    _placeSearchScrollController.dispose();
    _paneController.dispose();
    _replyBannerController.dispose();
    _disposePendingVideoController();
    super.dispose();
  }

  void _disposePendingVideoController() {
    _pendingVideoController?.dispose();
    _pendingVideoController = null;
    _pendingVideoInitialized = false;
  }

  Future<void> _setSelectedMedia(Media media) async {
    if (!mounted) return;

    if (media.type == MediaType.video) {
      _disposePendingVideoController();

      final controller = media.url.startsWith('http')
          ? VideoPlayerController.networkUrl(
              Uri.parse(buildOptimizedVideoUrl(media.url, maxWidth: 1280)),
            )
          : VideoPlayerController.file(File(media.url));

      setState(() {
        _selectedMediaForEntry = media;
        _selectedType = ThreadEntryType.media;
        _pendingVideoController = controller;
        _pendingVideoInitialized = false;
        _uploadProgress = null;
      });

      try {
        await controller.initialize();
        controller
          ..setLooping(true)
          ..setVolume(0)
          ..play();
        if (mounted) {
          setState(() {
            _pendingVideoInitialized = true;
          });
        }
      } catch (e) {
        debugPrint('[TripThread] Failed to initialize video preview: $e');
        if (mounted) {
          setState(() {
            _pendingVideoInitialized = false;
          });
        }
      }
    } else {
      _disposePendingVideoController();
      setState(() {
        _selectedMediaForEntry = media;
        _selectedType = ThreadEntryType.media;
        _uploadProgress = null;
      });
    }
  }

  void _clearSelectedMedia() {
    _disposePendingVideoController();
    setState(() {
      _selectedMediaForEntry = null;
      _uploadProgress = null;
      _pendingMediaBatch.clear();
    });
  }

  Future<void> _loadTripParticipants() async {
    try {
      final apiService = context.read<ApiService>();
      final participants = await apiService.getTripParticipants(widget.tripId);
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _tripParticipants = participants;
            });
            // Participants often arrive after "@"; rebuild so the menu appears.
            if (_mentionQuery != null) {
              setState(() {});
            }
          }
        });
      }
    } catch (e) {
      debugPrint('[TripThread] Failed to load participants: $e');
    }
  }

  bool _isMentionBoundaryWhitespace(String ch) {
    return ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r';
  }

  /// Participants from API plus trip owner when owner is not a [TripParticipant] row.
  List<TripParticipant> _mentionParticipantPool() {
    final out = List<TripParticipant>.from(_tripParticipants);
    final trip = _trip;
    if (trip == null) return out;
    final ownerId = trip.userId;
    final ownerUser = trip.user;
    final hasOwnerRow = out.any((p) => p.userId == ownerId);
    if (!hasOwnerRow && ownerUser != null) {
      out.add(
        TripParticipant(
          id: 'trip-owner-$ownerId',
          tripId: trip.id,
          userId: ownerId,
          role: 'owner',
          joinedAt: trip.createdAt,
          user: ownerUser,
        ),
      );
    }
    return out;
  }

  void _onTextChanged() {
    final text = _textController.text;
    final selection = _textController.selection;
    final cursorPosition = selection.baseOffset;

    if (cursorPosition < 0 || cursorPosition > text.length) {
      if (mounted) {
        setState(() {
          _mentionQuery = null;
          _mentionStartPosition = null;
        });
      }
      return;
    }

    final textBeforeCursor = text.substring(0, cursorPosition);
    final lastAtIndex = textBeforeCursor.lastIndexOf('@');

    if (lastAtIndex == -1) {
      if (mounted) {
        setState(() {
          _mentionQuery = null;
          _mentionStartPosition = null;
        });
      }
      return;
    }

    if (lastAtIndex > 0 &&
        !_isMentionBoundaryWhitespace(textBeforeCursor[lastAtIndex - 1])) {
      if (mounted) {
        setState(() {
          _mentionQuery = null;
          _mentionStartPosition = null;
        });
      }
      return;
    }

    final rawQuery = textBeforeCursor.substring(lastAtIndex + 1);
    if (rawQuery.contains(RegExp(r'\s'))) {
      if (mounted) {
        setState(() {
          _mentionQuery = null;
          _mentionStartPosition = null;
        });
      }
      return;
    }

    final query = rawQuery.toLowerCase();
    debugPrint(
      '[MentionMenu] Detected @ mention: query="$query", position=$lastAtIndex',
    );
    _mentionQuery = query;
    _mentionStartPosition = lastAtIndex;
    _showMentionMenu();
  }

  void _showMentionMenu() {
    // Trigger rebuild to show mention menu
    if (mounted) {
      setState(() {});
    }
  }

  void _selectMention(TripParticipant participant) {
    final username = participant.user?.username;
    if (_mentionStartPosition == null ||
        username == null ||
        username.isEmpty) {
      _mentionQuery = null;
      _mentionStartPosition = null;
      return;
    }

    final text = _textController.text;
    final start = _mentionStartPosition!;
    final beforeAt = text.substring(0, start);
    final afterCursor = text.substring(_textController.selection.baseOffset);
    final newText = '$beforeAt@$username $afterCursor';
    final newCursorPosition = start + username.length + 2; // +2 for @ and space

    _textController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursorPosition),
    );

    // Clear mention state
    _mentionQuery = null;
    _mentionStartPosition = null;
  }

  void _insertAllMention() {
    if (_mentionStartPosition == null) return;
    final text = _textController.text;
    final beforeAt = text.substring(0, _mentionStartPosition!);
    final afterCursor = text.substring(_textController.selection.baseOffset);
    const token = '@all ';
    final newText = '$beforeAt$token$afterCursor';
    final newCursor = _mentionStartPosition! + token.length;
    _textController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: newCursor.clamp(0, newText.length),
      ),
    );
    _mentionQuery = null;
    _mentionStartPosition = null;
    if (mounted) setState(() {});
  }

  List<String> _extractTaggedUsernames(String text) {
    final regex = RegExp(r'@(\w+)');
    final matches = regex.allMatches(text);
    return matches.map((m) => m.group(1)!).toList();
  }

  Future<void> _loadTrip() async {
    final tripProvider = context.read<TripProvider>();

    // Clear entries immediately to prevent showing old trip's entries
    tripProvider.clearCurrentTripEntries();

    // Set loading state
    if (mounted) {
      setState(() {
        _isLoading = true;
        _isLoadingEntries = true;
      });
    }

    final trip = await tripProvider.getTrip(widget.tripId);

    if (mounted) {
      setState(() {
        _trip = trip;
        _isLoading = false;
      });
      if (_mentionQuery != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      }

      if (trip != null) {
        await tripProvider.loadCurrentTripEntries(widget.tripId);
        _syncEntryEngagementState();

        final hl = widget.highlightEntryId;
        if (hl != null && hl.isNotEmpty) {
          final found = await tripProvider.loadUntilEntryPresent(
            widget.tripId,
            hl,
          );
          if (mounted) _syncEntryEngagementState();
          if (mounted && !found) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Jump target is older than the loaded history. Scroll up to load more.',
                ),
              ),
            );
          }
        }

        if (mounted) {
          setState(() {
            _isLoadingEntries = false;
          });
        }

        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final hl2 = widget.highlightEntryId;
            if (hl2 != null && hl2.isNotEmpty) {
              _scrollHighlightedEntryIntoView(hl2);
            } else {
              _scrollThreadToBottom(animated: false);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _scrollThreadToBottom(animated: false);
              });
            }
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoadingEntries = false;
          });
        }
      }
    }
  }

  void _syncEntryEngagementState() {
    final entries = context.read<TripProvider>().currentTripEntries;
    if (entries.isEmpty) return;
    final engagementProvider = context.read<EngagementProvider>();
    engagementProvider.syncLikeCounts({
      for (final entry in entries) entry.id: entry.likeCount,
    });
    engagementProvider.setLikeStatusBatch({
      for (final entry in entries) entry.id: entry.hasLiked,
    });
  }

  void _onThreadScrollNearTop() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels > 180) return;
    _maybeLoadOlderThreadEntries();
  }

  Future<void> _maybeLoadOlderThreadEntries() async {
    if (!mounted || _pendingOlderPageLoad) return;
    final tripProvider = context.read<TripProvider>();
    if (!tripProvider.threadEntriesHasMoreOlder ||
        tripProvider.isLoadingOlderThreadEntries) {
      return;
    }

    _pendingOlderPageLoad = true;
    final scroll = _scrollController;
    final oldPixels = scroll.hasClients ? scroll.position.pixels : 0.0;
    final oldMax = scroll.hasClients ? scroll.position.maxScrollExtent : 0.0;

    await tripProvider.loadOlderThreadEntries(widget.tripId);

    if (!mounted) {
      _pendingOlderPageLoad = false;
      return;
    }

    _syncEntryEngagementState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _pendingOlderPageLoad = false;
        return;
      }
      if (scroll.hasClients) {
        final newMax = scroll.position.maxScrollExtent;
        final delta = newMax - oldMax;
        final target = (oldPixels + delta).clamp(0.0, newMax);
        scroll.jumpTo(target);
      }
      _pendingOlderPageLoad = false;
    });
  }

  void _scrollThreadToBottom({bool animated = true}) {
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    if (max <= 0) return;
    if (animated) {
      _scrollController.animateTo(
        max,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scrollController.jumpTo(max);
    }
  }

  Future<void> _scrollHighlightedEntryIntoView(String entryId) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final key = _highlightEntryKeys[entryId];
      final ctx = key?.currentContext;
      if (ctx != null && ctx.mounted) {
        try {
          await Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            alignment: 0.12,
          );
        } catch (_) {}
        if (!mounted) return;
        return;
      }
    }
    _scrollThreadToBottom(animated: false);
  }

  Future<void> _addEntry() async {
    if (_isSubmitting) {
      debugPrint(
        '[TripThread] Submission already in progress, ignoring duplicate call',
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final tripProvider = context.read<TripProvider>();
    bool success = false;

    try {
      switch (_selectedType) {
        case ThreadEntryType.text:
          if (_textController.text.trim().isNotEmpty) {
            final text = _textController.text.trim();
            final taggedUsernames = _extractTaggedUsernames(text);
            success = await tripProvider.addTextEntry(
              text,
              tripId: widget.tripId,
              taggedUsernames: taggedUsernames.isNotEmpty
                  ? taggedUsernames
                  : null,
            );
            if (success) {
              _textController.clear();
              _mentionQuery = null;
              _mentionStartPosition = null;
            }
          }
          break;
        case ThreadEntryType.location:
          if (_selectedPlace != null) {
            debugPrint(
              '[TripThread] Adding location entry with placeId: ${_selectedPlace!.id}',
            );

            final text = _textController.text.trim();
            final taggedUsernames = text.isNotEmpty
                ? _extractTaggedUsernames(text)
                : <String>[];
            final usernamesToSend = taggedUsernames.isNotEmpty
                ? taggedUsernames
                : null;
            success = await tripProvider.addThreadEntryWithPlace(
              tripId: widget.tripId,
              type: ThreadEntryType.location,
              contentText: text.isNotEmpty ? text : null,
              placeId: _selectedPlace!.id,
              taggedUsernames: usernamesToSend,
            );
            if (!mounted) return;
            if (success) {
              setState(() {
                _selectedPlace = null;
                _locationController.clear();
                _textController.clear();
              });
              _mentionQuery = null;
              _mentionStartPosition = null;
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(tripProvider.error ?? 'Failed to add location'),
                ),
              );
            }
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Please select a location first')),
            );
            return;
          }
          break;
        case ThreadEntryType.media:
          success = await _handleMediaSubmission(tripProvider);
          break;
        case ThreadEntryType.checkin:
          if (_selectedPlace != null) {
            final text = _textController.text.trim();
            final taggedUsernames = text.isNotEmpty
                ? _extractTaggedUsernames(text)
                : <String>[];
            final usernamesToSend = taggedUsernames.isNotEmpty
                ? taggedUsernames
                : null;
            success = await tripProvider.addThreadEntryWithPlace(
              tripId: widget.tripId,
              type: ThreadEntryType.checkin,
              contentText: text.isNotEmpty ? text : null,
              placeId: _selectedPlace!.id,
              taggedUsernames: usernamesToSend,
            );
            if (success) {
              setState(() {
                _selectedPlace = null;
                _locationController.clear();
                _textController.clear();
              });
              _mentionQuery = null;
              _mentionStartPosition = null;
            }
          }
          break;
      }

      if (success) {
        setState(() {
          _replyingToEntry = null;
          _composerOpen = false;
        });
        _replyBannerController.reset();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _startReplyToEntry(TripThreadEntry entry) {
    HapticFeedback.selectionClick();
    final username = entry.author.username;
    final mentionPrefix = username != null && username.isNotEmpty
        ? '@$username '
        : '';

    setState(() {
      _replyingToEntry = entry;
      _selectedType = ThreadEntryType.text;
      _composerOpen = true;
    });

    if (mentionPrefix.isNotEmpty &&
        !_textController.text.trimLeft().startsWith(mentionPrefix)) {
      final existing = _textController.text.trimLeft();
      _textController.value = TextEditingValue(
        text: '$mentionPrefix$existing',
        selection: TextSelection.collapsed(
          offset: ('$mentionPrefix$existing').length,
        ),
      );
    }
    _replyBannerController.forward(from: 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _entryInputFocusNode.requestFocus();
    });
  }

  Future<void> _pickImage({bool fromCamera = false}) async {
    try {
      final mediaService = _mediaService ?? context.read<MediaService>();
      final file = await mediaService.pickImage(fromCamera: fromCamera);
      if (file != null) {
        final fileSize = await file.length();
        final media = Media(
          id: '',
          url: file.path,
          publicId: '',
          type: mediaService.getMediaType(file),
          filename: mediaService.getFileName(file),
          size: fileSize,
          width: null,
          height: null,
          duration: null,
          processingStatus: MediaProcessingStatus.pending,
          uploadedById: '',
          tripId: widget.tripId,
          createdAt: DateTime.now(),
        );
        await _setSelectedMedia(media);
        if (!mounted) return;
        setState(() {
          _pendingMediaBatch.clear();
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error picking image: $e')));
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final mediaService = _mediaService ?? context.read<MediaService>();
      final files = await mediaService.pickMultipleMedia();
      if (files.isEmpty) {
        return;
      }

      final newMediaItems = <Media>[];

      for (final file in files) {
        final fileSize = await file.length();
        newMediaItems.add(
          Media(
            id: '',
            url: file.path,
            publicId: '',
            type: mediaService.getMediaType(file),
            filename: mediaService.getFileName(file),
            size: fileSize,
            width: null,
            height: null,
            duration: null,
            processingStatus: MediaProcessingStatus.pending,
            uploadedById: '',
            tripId: widget.tripId,
            createdAt: DateTime.now(),
          ),
        );
      }

      const maxQueued = 10;
      final totalCount =
          (_selectedMediaForEntry == null ? 0 : 1) +
          _pendingMediaBatch.length +
          newMediaItems.length;
      if (totalCount > maxQueued) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'You can queue at most $maxQueued media items at once.',
            ),
          ),
        );
        return;
      }

      if (newMediaItems.isEmpty) {
        return;
      }

      if (_selectedMediaForEntry == null) {
        final first = newMediaItems.first;
        final remaining = newMediaItems.length > 1
            ? newMediaItems.sublist(1)
            : <Media>[];

        await _setSelectedMedia(first);
        if (!mounted) return;
        setState(() {
          _pendingMediaBatch = remaining;
        });
      } else {
        setState(() {
          _pendingMediaBatch = [..._pendingMediaBatch, ...newMediaItems];
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error picking media: $e')));
    }
  }

  Future<void> _pickVideo() async {
    try {
      final mediaService = _mediaService ?? context.read<MediaService>();
      final file = await mediaService.pickVideo();
      if (file != null) {
        final fileSize = await file.length();
        final media = Media(
          id: '',
          url: file.path,
          publicId: '',
          type: mediaService.getMediaType(file),
          filename: mediaService.getFileName(file),
          size: fileSize,
          width: null,
          height: null,
          duration: null,
          processingStatus: MediaProcessingStatus.pending,
          uploadedById: '',
          tripId: widget.tripId,
          createdAt: DateTime.now(),
        );
        await _setSelectedMedia(media);
        if (!mounted) return;
        setState(() {
          _pendingMediaBatch.clear();
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error picking video: $e')));
    }
  }

  Future<bool> _handleMediaSubmission(TripProvider tripProvider) async {
    if (_selectedMediaForEntry == null && _pendingMediaBatch.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one media file')),
      );
      return false;
    }

    final captionText = _textController.text.trim();
    final caption = captionText.isNotEmpty ? captionText : null;
    final taggedUsernames = captionText.isNotEmpty
        ? _extractTaggedUsernames(captionText)
        : <String>[];
    final usernamesToSend = taggedUsernames.isNotEmpty ? taggedUsernames : null;

    final allMedia = <Media>[
      if (_selectedMediaForEntry != null) _selectedMediaForEntry!,
      ..._pendingMediaBatch,
    ];

    if (allMedia.isEmpty) {
      return false;
    }

    bool allSucceeded = true;

    for (var index = 0; index < allMedia.length; index++) {
      final media = allMedia[index];

      if (index == 0) {
        setState(() {
          _isUploadingMedia = true;
          _uploadProgress = 0.0;
          _pendingMediaBatch = allMedia.length > 1
              ? allMedia.sublist(1)
              : <Media>[];
        });
      } else {
        await _setSelectedMedia(media);
        if (!mounted) return false;
        setState(() {
          _isUploadingMedia = true;
          _uploadProgress = 0.0;
          _pendingMediaBatch = allMedia.sublist(index + 1);
        });
      }

      try {
        final uploadedMedia = await _uploadSingleMediaForEntry(
          media,
          caption,
          usernamesToSend,
          tripProvider,
        );
        allMedia[index] = uploadedMedia;
        if (mounted) {
          setState(() {
            _pendingMediaBatch = allMedia.sublist(index + 1);
          });
        }
      } catch (e) {
        allSucceeded = false;
        if (mounted) {
          debugPrint(
            '[TripThread] Failed to upload media item ${index + 1}/${allMedia.length}: $e',
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Failed to upload media ${index + 1}/${allMedia.length}: $e',
              ),
            ),
          );
          setState(() {
            _isUploadingMedia = false;
            _uploadProgress = null;
            _pendingMediaBatch = allMedia.sublist(index + 1);
          });
        }
        continue;
      }
    }

    if (!mounted) {
      return allSucceeded;
    }

    if (allSucceeded) {
      _textController.clear();
      _clearSelectedMedia();
      _mentionQuery = null;
      _mentionStartPosition = null;
      setState(() {
        _isUploadingMedia = false;
        _uploadProgress = null;
        _pendingMediaBatch = [];
      });
    }

    return allSucceeded;
  }

  Future<Media> _uploadSingleMediaForEntry(
    Media media,
    String? caption,
    List<String>? taggedUsernames,
    TripProvider tripProvider,
  ) async {
    final mediaService = _mediaService ?? context.read<MediaService>();
    Media resolvedMedia = media;

    if (!media.url.startsWith('http')) {
      final uploadedMedia = await mediaService.uploadMediaToCloudinary(
        file: File(media.url),
        tripId: widget.tripId,
        usage: 'thread_entry',
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _uploadProgress = progress;
          });
        },
      );

      if (uploadedMedia == null) {
        throw Exception('Media upload failed');
      }

      resolvedMedia = uploadedMedia;
    } else {
      if (mounted) {
        setState(() {
          _uploadProgress = 1.0;
        });
      }
    }

    if (resolvedMedia.id.isEmpty) {
      throw Exception('Missing media identifier after upload');
    }

    final success = await tripProvider.addMediaEntry(
      resolvedMedia.id,
      caption: caption,
      tripId: widget.tripId,
      taggedUsernames: taggedUsernames,
    );

    if (!success) {
      throw Exception('Failed to save media entry');
    }

    if (mounted) {
      setState(() {
        _uploadProgress = 1.0;
        _selectedMediaForEntry = resolvedMedia;
      });
    }

    return resolvedMedia;
  }

  /// Leaves the thread without calling [context.pop] from a PopScope callback
  /// (that re-enters the navigator while locked and throws `!_debugLocked`).
  void _leaveThread({String? fallback}) {
    if (!mounted) return;
    final extra = GoRouterState.of(context).extra;
    final from = (extra is Map && extra['from'] != null)
        ? extra['from'] as String
        : (fallback ?? '/trip/${widget.tripId}');
    context.go(
      from,
      extra: from == '/home' ? {'explicitHome': true} : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          _leaveThread(fallback: '/home');
        },
        child: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    if (_trip == null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          _leaveThread(fallback: '/home');
        },
        child: Scaffold(
          appBar: AppBar(title: const Text('Trip Thread')),
          body: const Center(child: Text('Trip not found')),
        ),
      );
    }

    final currentUser = context.read<AuthProvider>().currentUser;
    final isMember = currentUser?.id == _trip!.userId ||
        _trip!.participants?.any((p) => p.userId == currentUser?.id) == true;
    final canAddEntries =
        _trip!.status == TripStatus.ongoing && isMember;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _leaveThread();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: Text(_trip?.title ?? 'Trip Thread'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _leaveThread,
          ),
          actions: [
            if (isMember)
              IconButton(
                tooltip: _moneyPaneSelected ? 'Trip thread' : 'Money',
                icon: Icon(
                  _moneyPaneSelected ? Icons.timeline : Icons.currency_rupee,
                ),
                onPressed: () {
                  final target = _moneyPaneSelected ? 0 : 1;
                  _paneController.animateToPage(
                    target,
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                  );
                },
              ),
          ],
        ),
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: Stack(
            key: _stackKey,
            clipBehavior: Clip.none,
            children: [
              if (isMember)
                PageView(
                  controller: _paneController,
                  onPageChanged: (index) {
                    setState(() {
                      _moneyPaneSelected = index == 1;
                    });
                  },
                  children: [
                    Column(
                      children: [
                        Expanded(child: _buildThreadList(canAddEntries)),
                        if (canAddEntries) _buildAddEntrySection(),
                        if (!canAddEntries)
                          SafeArea(
                            top: false,
                            child: TextButton.icon(
                              onPressed: () {
                                _paneController.animateToPage(
                                  1,
                                  duration: const Duration(milliseconds: 280),
                                  curve: Curves.easeOutCubic,
                                );
                              },
                              icon: const Icon(Icons.currency_rupee),
                              label: const Text('Money'),
                            ),
                          ),
                      ],
                    ),
                    TripMoneyPane(tripId: widget.tripId),
                  ],
                )
              else
                Column(
                  children: [
                    Expanded(child: _buildThreadList(canAddEntries)),
                    if (canAddEntries) _buildAddEntrySection(),
                  ],
                ),
              // Mention autocomplete menu - positioned relative to text field
              if (_mentionQuery != null)
                Builder(builder: (context) => _buildMentionMenu(context)),
              // Floating navigation button for ongoing trips
              const FloatingTripNavButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMentionMenu(BuildContext context) {
    final currentUserId = context.read<AuthProvider>().currentUser?.id;

    // Filter participants by query, excluding current user
    final query = _mentionQuery?.toLowerCase() ?? '';
    final pool = _mentionParticipantPool();
    final filtered = pool.where((p) {
      if (p.userId == currentUserId) return false;

      if (query.isEmpty) return true;

      final username = p.user?.username?.toLowerCase() ?? '';
      final name = p.user?.name?.toLowerCase() ?? '';
      return username.contains(query) || name.contains(query);
    }).toList();

    final othersOnTrip = pool.where((p) => p.userId != currentUserId).length;
    final showAllRow =
        othersOnTrip > 0 && (query.isEmpty || query == 'all');

    if (filtered.isEmpty && !showAllRow) return const SizedBox.shrink();

    final renderBox =
        _textFieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached) {
      debugPrint('[MentionMenu] Text field render box not available');
      return const SizedBox.shrink();
    }

    final stackRenderBox =
        _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackRenderBox == null || !stackRenderBox.attached) {
      debugPrint('[MentionMenu] Stack render box not available');
      return const SizedBox.shrink();
    }

    final globalPosition = renderBox.localToGlobal(Offset.zero);
    final stackGlobalPosition = stackRenderBox.localToGlobal(Offset.zero);
    final relativePosition = globalPosition - stackGlobalPosition;

    final size = renderBox.size;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final stackSize = stackRenderBox.size;

    if (!stackSize.height.isFinite ||
        !stackSize.width.isFinite ||
        stackSize.height <= 0 ||
        stackSize.width <= 0) {
      return const SizedBox.shrink();
    }

    final hasKeyboard = keyboardHeight > 0;
    final menuWidth = size.width
        .clamp(120.0, 400.0)
        .toDouble()
        .clamp(0.0, stackSize.width);
    final maxMenuLeft = (stackSize.width - menuWidth).clamp(
      0.0,
      stackSize.width,
    );
    final menuLeft = relativePosition.dx.clamp(0.0, maxMenuLeft);

    double menuTop;
    final maxTop = (stackSize.height - 100.0).clamp(0.0, stackSize.height);
    if (hasKeyboard) {
      menuTop = (relativePosition.dy - 8).clamp(0.0, maxTop);
    } else {
      menuTop = (relativePosition.dy + size.height + 8).clamp(0.0, maxTop);
    }

    final spaceAbove = menuTop;
    final spaceBelow = stackSize.height - menuTop;
    var availableHeight = hasKeyboard ? spaceAbove : spaceBelow;
    if (!availableHeight.isFinite || availableHeight < 56) {
      availableHeight = (stackSize.height * 0.35).clamp(56.0, 280.0);
    }
    const itemHeight = 56.0;
    final maxItems = (availableHeight / itemHeight).floor().clamp(1, 5);
    final maxUserSlots = (maxItems - (showAllRow ? 1 : 0)).clamp(0, maxItems);
    final shownUsers = filtered.length > maxUserSlots
        ? filtered.sublist(0, maxUserSlots)
        : filtered;
    final totalRows = (showAllRow ? 1 : 0) + shownUsers.length;
    if (totalRows == 0) return const SizedBox.shrink();

    final maxHeightCap =
        (stackSize.height * 0.7).clamp(36.0, 280.0).toDouble();
    final minHeightCap = maxHeightCap < 44.0 ? maxHeightCap : 44.0;
    final desiredHeight = totalRows * itemHeight;
    var menuHeight = desiredHeight.clamp(minHeightCap, maxHeightCap);
    if (!menuHeight.isFinite || menuHeight <= 0) {
      menuHeight = 200.0;
    }

    debugPrint(
      '[MentionMenu] Showing menu: query="$query", users=${shownUsers.length}, allRow=$showAllRow, position=($menuLeft, $menuTop), width=$menuWidth, keyboard=$hasKeyboard',
    );

    return Positioned(
      left: menuLeft,
      top: menuTop,
      width: menuWidth,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: menuHeight,
            minHeight: minHeightCap,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.outline.withValues(alpha: 0.2),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: totalRows,
            itemBuilder: (context, index) {
              if (showAllRow && index == 0) {
                return ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 0,
                  ),
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .secondaryContainer,
                    child: Icon(
                      Icons.groups,
                      size: 18,
                      color: Theme.of(context)
                          .colorScheme
                          .onSecondaryContainer,
                    ),
                  ),
                  title: const Text(
                    'Everyone on this trip',
                    style: TextStyle(fontSize: 14),
                  ),
                  subtitle: Text(
                    '@all',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  onTap: _insertAllMention,
                );
              }
              final pi = showAllRow ? index - 1 : index;
              final participant = shownUsers[pi];
              final user = participant.user;
              return ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 0,
                ),
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  backgroundImage: user?.avatarUrl != null
                      ? NetworkImage(user!.avatarUrl!)
                      : null,
                  child: user?.avatarUrl == null
                      ? Text(
                          user?.name?.substring(0, 1).toUpperCase() ?? 'U',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                          ),
                        )
                      : null,
                ),
                title: Text(
                  user?.name ?? 'User',
                  style: const TextStyle(fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: user?.username != null
                    ? Text(
                        user!.username!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      )
                    : null,
                onTap: () => _selectMention(participant),
              );
            },
          ),
        ),
      ),
    );
  }

  Map<String, String> _usernameToUserIdFromTagged(List<User>? tagged) {
    if (tagged == null || tagged.isEmpty) return {};
    final map = <String, String>{};
    for (final u in tagged) {
      if (u.username != null && u.username!.isNotEmpty) {
        map[u.username!] = u.id;
      }
    }
    return map;
  }

  bool _canModerateThreadEntry(TripThreadEntry entry) {
    final uid = context.read<AuthProvider>().currentUser?.id;
    if (uid == null) return false;
    if (entry.authorId == uid) return true;
    final ownerId = _trip?.userId;
    return ownerId != null && ownerId == uid;
  }

  /// Authors may edit text only within 15 minutes. Trip owner (non-author) may still edit for moderation.
  bool _canEditThreadEntryText(TripThreadEntry entry) {
    if (entry.type != ThreadEntryType.text) return false;
    if (_trip?.status != TripStatus.ongoing) return false;
    final uid = context.read<AuthProvider>().currentUser?.id;
    if (uid == null) return false;
    final isAuthor = entry.authorId == uid;
    final isTripOwner = _trip?.userId == uid;
    if (!isAuthor && !isTripOwner) return false;
    if (isAuthor) {
      if (DateTime.now().difference(entry.createdAt) >
          const Duration(minutes: 15)) {
        return false;
      }
    }
    return true;
  }

  Widget _threadEntryActionSheetRow({
    required BuildContext sheetCtx,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? foregroundColor,
  }) {
    final color = foregroundColor ?? Theme.of(sheetCtx).colorScheme.onSurface;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(sheetCtx).textTheme.titleMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showThreadEntryActions(TripThreadEntry entry) async {
    if (!mounted || _trip?.status != TripStatus.ongoing) return;
    if (!_canModerateThreadEntry(entry)) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) {
        final errorColor = Theme.of(sheetCtx).colorScheme.error;
        return SafeArea(
          child: Material(
            color: Theme.of(sheetCtx).colorScheme.surface,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_canEditThreadEntryText(entry))
                    _threadEntryActionSheetRow(
                      sheetCtx: sheetCtx,
                      icon: Icons.edit_outlined,
                      label: 'Edit text',
                      onTap: () {
                        Navigator.pop(sheetCtx);
                        _showEditTextEntryDialog(entry);
                      },
                    ),
                  _threadEntryActionSheetRow(
                    sheetCtx: sheetCtx,
                    icon: Icons.delete_outline,
                    label: 'Delete entry',
                    foregroundColor: errorColor,
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      _confirmDeleteThreadEntry(entry);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showEditTextEntryDialog(TripThreadEntry entry) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;

    final text = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => _EditThreadEntryDialog(
        initialText: entry.contentText ?? '',
      ),
    );
    if (!mounted || text == null) return;

    final tripProvider = context.read<TripProvider>();
    final success = await tripProvider.updateThreadEntryText(
      tripId: widget.tripId,
      entryId: entry.id,
      contentText: text,
    );
    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Entry updated')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tripProvider.error ?? 'Could not update entry')),
      );
    }
  }

  Future<void> _confirmDeleteThreadEntry(TripThreadEntry entry) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: const Text(
          'This removes the entry from the thread and the trip map. '
          'Media will be removed from storage when applicable.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogCtx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted || confirm != true) return;

    final tripProvider = context.read<TripProvider>();
    final engagement = context.read<EngagementProvider>();
    final success = await tripProvider.deleteThreadEntry(
      tripId: widget.tripId,
      entryId: entry.id,
    );
    if (!mounted) return;
    if (success) {
      engagement.clearEntity(entry.id);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Entry deleted')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tripProvider.error ?? 'Could not delete entry')),
      );
    }
  }

  Widget _buildThreadEntry(TripThreadEntry entry, {required bool isLast}) {
    GlobalKey? highlightKey;
    final hid = widget.highlightEntryId;
    if (hid != null && hid.isNotEmpty && hid == entry.id) {
      highlightKey = _highlightEntryKeys[entry.id] ??= GlobalKey();
    }

    final card = ThreadEntryCard(
      entry: entry,
      isLast: isLast,
      showRail: AppLayout.showThreadRail(context),
      canModerate: _trip?.status == TripStatus.ongoing &&
          _canModerateThreadEntry(entry),
      onOpenActions: () => _showThreadEntryActions(entry),
      onReply: () => _startReplyToEntry(entry),
      usernameToUserId: _usernameToUserIdFromTagged(entry.taggedUsers),
      media: entry.type == ThreadEntryType.media ? _buildMediaPreview(entry) : null,
    );

    if (highlightKey != null) {
      return KeyedSubtree(key: highlightKey, child: card);
    }
    return card;
  }

  Widget _buildMediaPreview(TripThreadEntry entry) {
    final mediaUrl = entry.media?.url;
    if (mediaUrl == null || mediaUrl.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurface.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.06
                : 0.03,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.image_not_supported_outlined, color: Colors.grey),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Media not available',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final isVideo = entry.media?.type == MediaType.video;
    final heroTag = 'trip-media-${entry.id}';
    final previewUrl = isVideo
        ? buildVideoThumbnailUrl(mediaUrl, maxWidth: 960)
        : buildOptimizedImageUrl(mediaUrl, width: 1080);

    return GestureDetector(
      onTap: () => _openMediaViewer(heroTag, mediaUrl, isVideo),
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Hero(
                tag: heroTag,
                child: Image.network(
                  previewUrl,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  gaplessPlayback: true,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return ColoredBox(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      child: const Center(child: CircularProgressIndicator()),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Theme.of(context).colorScheme.onSurface.withValues(
                        alpha: Theme.of(context).brightness == Brightness.dark
                            ? 0.06
                            : 0.03,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.broken_image,
                            size: 48,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Failed to load media',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              if (isVideo)
                Align(
                  alignment: Alignment.center,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _openMediaViewer(String heroTag, String mediaUrl, bool isVideo) {
    if (isVideo) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              _TripVideoViewer(heroTag: heroTag, mediaUrl: mediaUrl),
          fullscreenDialog: true,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            color: Colors.black.withValues(alpha: 0.95),
            child: SafeArea(
              child: Stack(
                children: [
                  Center(
                    child: Hero(
                      tag: heroTag,
                      child: InteractiveViewer(
                        maxScale: 5.0,
                        minScale: 0.5,
                        child: Image.network(
                          buildOptimizedImageUrl(mediaUrl, width: 2400),
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.broken_image_outlined,
                                    color: Colors.white70,
                                    size: 64,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Unable to load media.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(color: Colors.white70),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  if (isVideo)
                    Positioned(
                      bottom: 24,
                      left: 0,
                      right: 0,
                      child: Column(
                        children: [
                          const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 48,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Video playback coming soon',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  Positioned(
                    top: 16,
                    right: 16,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, color: Colors.white),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Max height for the bottom compose panel. When the keyboard is open, cap
  /// aggressively so the thread list keeps most of the viewport (fixes entries
  /// hidden behind keyboard + bottom overflow on location + comment).
  double _composePanelMaxHeight(MediaQueryData mediaQuery) {
    final keyboardInset = mediaQuery.viewInsets.bottom;
    final screenHeight = mediaQuery.size.height;
    final safeVerticalPadding =
        mediaQuery.padding.top + mediaQuery.padding.bottom;
    final availableHeight = (screenHeight - safeVerticalPadding).clamp(
      200.0,
      screenHeight,
    );

    if (keyboardInset > 0) {
      final aboveKeyboard = (availableHeight - keyboardInset).clamp(160.0, availableHeight);
      // Leave ~55%+ of space above the keyboard for the thread list.
      final cap = aboveKeyboard * 0.42;
      return cap.clamp(140.0, 300.0);
    }

    return (screenHeight * 0.48).clamp(
      availableHeight * 0.32,
      availableHeight * 0.55,
    );
  }

  Widget _buildThreadList(bool canAddEntries) {
    return Consumer<TripProvider>(
      builder: (context, tripProvider, child) {
        final allEntries = tripProvider.currentTripEntries;
        final entries = allEntries
            .where((entry) => entry.tripId == widget.tripId)
            .toList();

        if (_isLoadingEntries && entries.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (entries.isEmpty) {
          return CustomScrollView(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: _DashedPanel(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 40,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.maps_ugc_outlined,
                              size: 36,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant
                                  .withValues(alpha: 0.45),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No updates yet',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context).colorScheme.onSurface,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              canAddEntries
                                  ? 'Be the first to post an update.'
                                  : 'Updates will appear here as the trip unfolds.',
                              style: Theme.of(context).textTheme.bodyMedium,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        return AppLayout.reading(
          context: context,
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              return _buildThreadEntry(
                entries[index],
                isLast: index == entries.length - 1,
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildAddEntrySection() {
    final mediaQuery = MediaQuery.of(context);
    final maxHeight = _composePanelMaxHeight(mediaQuery);

    if (!_composerOpen) {
      final user = context.read<AuthProvider>().currentUser;
      return Material(
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          top: false,
          child: InkWell(
            onTap: () {
              setState(() => _composerOpen = true);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _entryInputFocusNode.requestFocus();
              });
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: AppTheme.muted,
                    backgroundImage: user?.avatarUrl != null
                        ? NetworkImage(user!.avatarUrl!)
                        : null,
                    child: user?.avatarUrl == null
                        ? Text(
                            (user?.name ?? 'U').substring(0, 1).toUpperCase(),
                            style: const TextStyle(
                              color: AppTheme.ink,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Post a trip update…',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.accent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Post',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: const Border(top: BorderSide(color: AppTheme.accent)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: SafeArea(
            top: false,
            left: false,
            right: false,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        setState(() => _composerOpen = false);
                        _entryInputFocusNode.unfocus();
                      },
                      child: const Text('Cancel'),
                    ),
                  ),
                  Row(
                    children: [
                      for (final type in const [
                        ThreadEntryType.text,
                        ThreadEntryType.media,
                        ThreadEntryType.location,
                      ])
                        Expanded(child: _composerTypeTab(type)),
                    ],
                  ),

                  const SizedBox(height: 12),

                  if (_replyingToEntry != null) ...[
                    FadeTransition(
                      opacity: _replyBannerFadeAnimation,
                      child: ScaleTransition(
                        scale: _replyBannerScaleAnimation,
                        child: Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.reply,
                                size: 16,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Replying to ${_replyingToEntry!.author.name ?? _replyingToEntry!.author.username ?? 'entry'}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                          ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if ((_replyingToEntry!.contentText ?? '')
                                        .isNotEmpty)
                                      Text(
                                        _replyingToEntry!.contentText!,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                            ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () {
                                  setState(() {
                                    _replyingToEntry = null;
                                  });
                                  _replyBannerController.reset();
                                },
                                icon: const Icon(Icons.close, size: 18),
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 24,
                                  minHeight: 24,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],

                  // LOCATION SELECTOR - Made scrollable and more spacious
                  if (_selectedType == ThreadEntryType.location ||
                      _selectedType == ThreadEntryType.checkin)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Search field
                        InkWell(
                          onTap: () async {
                            final place = await showModalBottomSheet<Place>(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (context) => PlaceSearchSheet(
                                controller: _placeSearchScrollController,
                              ),
                            );

                            if (place != null) {
                              setState(() {
                                _selectedPlace = place;
                                _locationController.text = place.name;
                              });
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Theme.of(context).colorScheme.onSurface
                                    .withValues(
                                      alpha:
                                          Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? 0.18
                                          : 0.10,
                                    ),
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.search,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _selectedPlace != null
                                      ? Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              _selectedPlace!.name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w500,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            if (_selectedPlace!.address != null)
                                              Text(
                                                _selectedPlace!.address!,
                                                style: TextStyle(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                  fontSize: 12,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                          ],
                                        )
                                      : Text(
                                          'Search for a location',
                                          style: TextStyle(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                ),
                                if (_selectedPlace != null)
                                  IconButton(
                                    icon: const Icon(Icons.close, size: 20),
                                    onPressed: () {
                                      setState(() {
                                        _selectedPlace = null;
                                        _locationController.clear();
                                      });
                                    },
                                    padding: const EdgeInsets.all(8),
                                    constraints: const BoxConstraints(),
                                    visualDensity: VisualDensity.compact,
                                  ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // "OR" divider
                        Row(
                          children: [
                            Expanded(
                              child: Divider(
                                color: Theme.of(context).colorScheme.onSurface
                                    .withValues(
                                      alpha:
                                          Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? 0.18
                                          : 0.10,
                                    ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Text(
                                'OR',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Divider(
                                color: Theme.of(context).colorScheme.onSurface
                                    .withValues(
                                      alpha:
                                          Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? 0.18
                                          : 0.10,
                                    ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // Map picker button
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.map),
                            label: const Text('Pick on Map'),
                            onPressed: () async {
                              final place = await Navigator.of(context)
                                  .push<Place>(
                                    MaterialPageRoute(
                                      fullscreenDialog: true,
                                      builder: (context) => MapPickerModal(
                                        initialPlaceName: _selectedPlace?.name,
                                        initialLat: _selectedPlace?.lat,
                                        initialLng: _selectedPlace?.lng,
                                      ),
                                    ),
                                  );

                              if (place != null) {
                                setState(() {
                                  _selectedPlace = place;
                                  _locationController.text = place.name;
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),

                  // MEDIA SELECTION - Made more compact and flexible
                  if (_selectedType == ThreadEntryType.media)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Media preview section - wrapped in Flexible to prevent overflow
                        if (_selectedMediaForEntry != null)
                          Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.15),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.25),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildPendingMediaThumbnail(),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            _selectedMediaForEntry!.filename ??
                                                'Selected media',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurface,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _selectedMediaForEntry!.size != null
                                                ? '${(_selectedMediaForEntry!.size! / 1024 / 1024).toStringAsFixed(1)} MB'
                                                : 'Selected',
                                            style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                              fontSize: 12,
                                            ),
                                          ),
                                          if (_selectedMediaForEntry!.type ==
                                                  MediaType.video &&
                                              _pendingVideoController != null)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 2.0,
                                              ),
                                              child: Text(
                                                _pendingVideoInitialized
                                                    ? _formatDuration(
                                                        _pendingVideoController!
                                                            .value
                                                            .duration,
                                                      )
                                                    : 'Loading preview...',
                                                style: TextStyle(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: _isUploadingMedia
                                          ? null
                                          : _clearSelectedMedia,
                                      icon: const Icon(Icons.close, size: 20),
                                      style: IconButton.styleFrom(
                                        backgroundColor: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.12),
                                        foregroundColor: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.all(8),
                                      ),
                                    ),
                                  ],
                                ),
                                if (_pendingMediaBatch.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white12,
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Text(
                                        '${_pendingMediaBatch.length} more ${_pendingMediaBatch.length == 1 ? 'item' : 'items'} queued',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ),
                                if (_isUploadingMedia)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 12.0),
                                    child: LinearProgressIndicator(
                                      value: _uploadProgress?.clamp(0.0, 1.0),
                                      backgroundColor: Colors.white12,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.secondary,
                                      minHeight: 6,
                                    ),
                                  ),
                              ],
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.all(8),
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Theme.of(context).colorScheme.onSurface
                                    .withValues(
                                      alpha:
                                          Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? 0.18
                                          : 0.10,
                                    ),
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final isWide = constraints.maxWidth > 400;
                                if (isWide) {
                                  return Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: _isUploadingMedia
                                              ? null
                                              : _pickFromGallery,
                                          icon: const Icon(
                                            Icons.photo_library,
                                            size: 18,
                                          ),
                                          label: const Text('Gallery'),
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 8,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: _isUploadingMedia
                                              ? null
                                              : () => _pickImage(
                                                  fromCamera: true,
                                                ),
                                          icon: const Icon(
                                            Icons.camera_alt,
                                            size: 18,
                                          ),
                                          label: const Text('Camera'),
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 8,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: _isUploadingMedia
                                              ? null
                                              : _pickVideo,
                                          icon: const Icon(
                                            Icons.video_file,
                                            size: 18,
                                          ),
                                          label: const Text('Video'),
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 8,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                }

                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: _isUploadingMedia
                                                ? null
                                                : _pickFromGallery,
                                            icon: const Icon(
                                              Icons.photo_library,
                                              size: 18,
                                            ),
                                            label: const Text('Gallery'),
                                            style: OutlinedButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 8,
                                                  ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: _isUploadingMedia
                                                ? null
                                                : () => _pickImage(
                                                    fromCamera: true,
                                                  ),
                                            icon: const Icon(
                                              Icons.camera_alt,
                                              size: 18,
                                            ),
                                            label: const Text('Camera'),
                                            style: OutlinedButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 8,
                                                  ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        onPressed: _isUploadingMedia
                                            ? null
                                            : _pickVideo,
                                        icon: const Icon(
                                          Icons.video_file,
                                          size: 18,
                                        ),
                                        label: const Text('Video'),
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 8,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                      ],
                    ),

                  // TEXT INPUT + SEND BUTTON - Compact and responsive
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          key: _textFieldKey,
                          controller: _textController,
                          focusNode: _entryInputFocusNode,
                          autofocus: false,
                          decoration: InputDecoration(
                            hintText: _getInputHint(),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            isDense: true,
                          ),
                          maxLines: 2,
                          minLines: 1,
                          textCapitalization: TextCapitalization.sentences,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Consumer<TripProvider>(
                        builder: (context, tripProvider, child) {
                          return IconButton(
                            onPressed:
                                (tripProvider.isLoading ||
                                    _isUploadingMedia ||
                                    _isSubmitting ||
                                    ((_selectedType ==
                                                ThreadEntryType.location ||
                                            _selectedType ==
                                                ThreadEntryType.checkin) &&
                                        _selectedPlace == null))
                                ? null
                                : _addEntry,
                            icon:
                                (tripProvider.isLoading ||
                                    _isUploadingMedia ||
                                    _isSubmitting)
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.send),
                            style: IconButton.styleFrom(
                              backgroundColor: AppTheme.accent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.all(12),
                            ),
                          );
                        },
                      ),
                    ],
                  ),

                  // ERROR MESSAGE - Compact
                  Consumer<TripProvider>(
                    builder: (context, tripProvider, child) {
                      if (tripProvider.error != null) {
                        return Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            tripProvider.error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 12,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _composerTypeTab(ThreadEntryType type) {
    final selected = _selectedType == type;
    final color = selected ? AppTheme.accent : Theme.of(context).colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedType = type;
          _moneyPaneSelected = false;
        });
        if (_paneController.hasClients) {
          _paneController.animateToPage(
            0,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppTheme.accentSoft : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: selected ? AppTheme.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_composerTypeIcon(type), size: 16, color: color),
            const SizedBox(height: 2),
            Text(
              _getEntryTypeLabel(type),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _composerTypeIcon(ThreadEntryType type) {
    switch (type) {
      case ThreadEntryType.text:
        return Icons.notes_rounded;
      case ThreadEntryType.media:
        return Icons.photo_camera_outlined;
      case ThreadEntryType.location:
        return Icons.place_outlined;
      case ThreadEntryType.checkin:
        return Icons.near_me_outlined;
    }
  }

  String _getEntryTypeLabel(ThreadEntryType type) {
    switch (type) {
      case ThreadEntryType.text:
        return 'Text';
      case ThreadEntryType.media:
        return 'Media';
      case ThreadEntryType.location:
        return 'Location';
      case ThreadEntryType.checkin:
        return 'Check-in';
    }
  }

  String _getInputHint() {
    switch (_selectedType) {
      case ThreadEntryType.text:
        return 'Share your thoughts...';
      case ThreadEntryType.media:
        return 'Add a caption...';
      case ThreadEntryType.location:
        return _selectedPlace != null
            ? 'Add notes about ${_selectedPlace!.name}...'
            : 'Select a location above...';
      case ThreadEntryType.checkin:
        return _selectedPlace != null
            ? 'How was ${_selectedPlace!.name}?'
            : 'Select a place to check in...';
    }
  }

  Widget _buildPendingMediaThumbnail() {
    final media = _selectedMediaForEntry!;
    final borderRadius = BorderRadius.circular(10);

    Widget content;
    if (media.type == MediaType.image) {
      final imageWidget = media.url.startsWith('http')
          ? Image.network(
              buildOptimizedImageUrl(media.url, width: 360, height: 360),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                color: Theme.of(context).colorScheme.onSurface.withValues(
                  alpha: Theme.of(context).brightness == Brightness.dark
                      ? 0.18
                      : 0.10,
                ),
                child: const Icon(Icons.broken_image, color: Colors.grey),
              ),
            )
          : Image.file(
              File(media.url),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                color: Theme.of(context).colorScheme.onSurface.withValues(
                  alpha: Theme.of(context).brightness == Brightness.dark
                      ? 0.18
                      : 0.10,
                ),
                child: const Icon(Icons.broken_image, color: Colors.grey),
              ),
            );
      content = imageWidget;
    } else {
      if (_pendingVideoController != null && _pendingVideoInitialized) {
        content = Stack(
          fit: StackFit.expand,
          children: [
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _pendingVideoController!.value.size.width,
                height: _pendingVideoController!.value.size.height,
                child: VideoPlayer(_pendingVideoController!),
              ),
            ),
            const Align(
              alignment: Alignment.center,
              child: Icon(
                Icons.play_circle_fill,
                color: Colors.white,
                size: 36,
              ),
            ),
          ],
        );
      } else {
        content = media.url.startsWith('http')
            ? Image.network(
                buildVideoThumbnailUrl(media.url, maxWidth: 360),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: Colors.black54,
                  child: const Center(
                    child: Icon(Icons.videocam, color: Colors.white, size: 32),
                  ),
                ),
              )
            : Container(
                color: Colors.black54,
                child: const Center(
                  child: Icon(Icons.videocam, color: Colors.white, size: 32),
                ),
              );
      }
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(width: 72, height: 72, child: content),
    );
  }

  String _formatDuration(Duration duration) {
    if (duration.inHours >= 1) {
      final hours = duration.inHours;
      final minutes = duration.inMinutes
          .remainder(60)
          .toString()
          .padLeft(2, '0');
      final seconds = duration.inSeconds
          .remainder(60)
          .toString()
          .padLeft(2, '0');
      return '$hours:$minutes:$seconds';
    } else {
      final minutes = duration.inMinutes.toString().padLeft(2, '0');
      final seconds = duration.inSeconds
          .remainder(60)
          .toString()
          .padLeft(2, '0');
      return '$minutes:$seconds';
    }
  }
}

class _EditThreadEntryDialog extends StatefulWidget {
  final String initialText;

  const _EditThreadEntryDialog({required this.initialText});

  @override
  State<_EditThreadEntryDialog> createState() => _EditThreadEntryDialogState();
}

class _EditThreadEntryDialogState extends State<_EditThreadEntryDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Text cannot be empty')),
      );
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Edit entry'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 3,
        maxLines: 8,
        maxLength: 1000,
        decoration: const InputDecoration(
          hintText: 'Update your message',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _TripVideoViewer extends StatefulWidget {
  final String heroTag;
  final String mediaUrl;

  const _TripVideoViewer({required this.heroTag, required this.mediaUrl});

  @override
  State<_TripVideoViewer> createState() => _TripVideoViewerState();
}

class _TripVideoViewerState extends State<_TripVideoViewer> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isPlaying = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      // Use original URL directly for videos - Cloudinary serves videos as-is
      // Only apply transformations if needed for bandwidth optimization
      final videoUrl = widget.mediaUrl.contains('/upload/')
          ? buildOptimizedVideoUrl(widget.mediaUrl, maxWidth: 1920)
          : widget.mediaUrl;

      debugPrint('[TripVideoViewer] Initializing video: $videoUrl');

      _controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));

      await _controller!.initialize();

      if (!mounted) {
        _controller?.dispose();
        return;
      }

      setState(() {
        _isInitialized = true;
      });

      _controller!
        ..setLooping(true)
        ..play();
    } catch (e, stackTrace) {
      debugPrint('[TripVideoViewer] Failed to initialize video: $e');
      debugPrint('[TripVideoViewer] Stack trace: $stackTrace');

      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load video. Please try again.';
        });
      }

      _controller?.dispose();
      _controller = null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlayback() {
    if (!_isInitialized || _controller == null) return;
    setState(() {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
        _isPlaying = false;
      } else {
        _controller!.play();
        _isPlaying = true;
      }
    });
  }

  void _retry() {
    setState(() {
      _errorMessage = null;
      _isInitialized = false;
    });
    _initializeVideo();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Hero(
                tag: widget.heroTag,
                child: _errorMessage != null
                    ? Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Colors.white70,
                              size: 64,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _errorMessage!,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 16,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              onPressed: _retry,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                              ),
                            ),
                          ],
                        ),
                      )
                    : _isInitialized && _controller != null
                    ? GestureDetector(
                        onTap: _togglePlayback,
                        child: AspectRatio(
                          aspectRatio: _controller!.value.aspectRatio,
                          child: VideoPlayer(_controller!),
                        ),
                      )
                    : const CircularProgressIndicator(color: Colors.white),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Colors.white),
                style: IconButton.styleFrom(backgroundColor: Colors.black45),
              ),
            ),
            if (_isInitialized)
              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: Center(
                  child: IconButton(
                    onPressed: _togglePlayback,
                    icon: Icon(
                      _isPlaying ? Icons.pause_circle : Icons.play_circle,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DashedPanel extends StatelessWidget {
  final Widget child;

  const _DashedPanel({required this.child});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outlineVariant;
    return CustomPaint(
      painter: _DashedRRectPainter(color: color),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(16),
        ),
        child: child,
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  final Color color;

  _DashedRRectPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(16),
    );
    final path = Path()..addRRect(rrect);
    const dash = 6.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color;
}
