import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/models/place.dart';
import 'package:tripthread/models/trip.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/providers/engagement_provider.dart';
import 'package:tripthread/providers/feed_provider.dart';
import 'package:tripthread/utils/app_theme.dart';
import 'package:tripthread/utils/cloudinary_utils.dart';
import 'package:tripthread/utils/feed_card_format.dart';
import 'package:tripthread/utils/map_place_label.dart';
import 'package:tripthread/widgets/engagement/engagement_action_bar.dart';
import 'package:tripthread/widgets/sheets/comment_bottom_sheet.dart';
import 'package:tripthread/widgets/sheets/share_bottom_sheet.dart';


Color _panel(BuildContext context) =>
    AppTheme.feedPanel(Theme.of(context).brightness);
Color _panelInk(BuildContext context) =>
    AppTheme.feedPanelInk(Theme.of(context).brightness);
Color _mutedSurface(BuildContext context) =>
    AppTheme.feedMutedSurface(Theme.of(context).brightness);
Color _mutedText(BuildContext context) =>
    AppTheme.feedMutedText(Theme.of(context).brightness);
Color _chipFill(BuildContext context) =>
    AppTheme.mediaChipFill(Theme.of(context).brightness);
Color _chipInk(BuildContext context) =>
    AppTheme.mediaChipInk(Theme.of(context).brightness);

/// Home-feed final-post card with author-chosen template bodies.
class FinalPostFeedCard extends StatelessWidget {
  final TripFinalPost post;
  final Future<void> Function(BuildContext context, TripFinalPost post)?
      onDelete;

  const FinalPostFeedCard({
    super.key,
    required this.post,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final authUserId = context.read<AuthProvider>().currentUser?.id;
    final author = post.displayAuthor;
    final authorId = post.displayAuthorId;
    final isOwner =
        authUserId != null && authorId != null && authUserId == authorId;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FeedCardHeader(
            post: post,
            author: author,
            authorId: authorId,
            isOwner: isOwner,
            onDelete: onDelete,
          ),
          // Posts without a trip stay postcard: no trip map-first or thread reel.
          if (post.isDirectPost)
            _PostcardBody(post: post)
          else
            switch (post.templateChoice) {
              FinalPostTemplateChoice.mapFirst => _MapFirstBody(post: post),
              FinalPostTemplateChoice.threadReel => _ThreadReelBody(post: post),
              FinalPostTemplateChoice.postcard => _PostcardBody(post: post),
            },
          _FeedCardFooter(post: post),
        ],
      ),
    );
  }
}

class _FeedCardHeader extends StatelessWidget {
  final TripFinalPost post;
  final dynamic author;
  final String? authorId;
  final bool isOwner;
  final Future<void> Function(BuildContext context, TripFinalPost post)?
      onDelete;

  const _FeedCardHeader({
    required this.post,
    required this.author,
    required this.authorId,
    required this.isOwner,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 8, 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              if (authorId != null) context.push('/profile/$authorId');
            },
            child: CircleAvatar(
              radius: 20,
              backgroundColor: AppTheme.avatarFallbackBackground(
                Theme.of(context).brightness,
              ),
              backgroundImage: author?.avatarUrl != null
                  ? NetworkImage(author!.avatarUrl as String)
                  : null,
              child: author?.avatarUrl == null
                  ? Icon(
                      Icons.person,
                      color: AppTheme.avatarFallbackForeground(
                        Theme.of(context).brightness,
                      ),
                      size: 20,
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () {
                    if (authorId != null) context.push('/profile/$authorId');
                  },
                  child: Text(
                    author?.name ?? author?.username ?? 'Travel Story',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                Text(
                  formatFeedCardSubtitle(post),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _mutedText(context),
                      ),
                ),
              ],
            ),
          ),
          if (isOwner)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) async {
                if (!context.mounted) return;
                if (value == 'edit') {
                  if (post.isDirectPost) {
                    context.push('/compose/${post.id}');
                  } else if ((post.tripId ?? '').isNotEmpty) {
                    context.push('/trip/${post.tripId}/final-post');
                  }
                } else if (value == 'delete' && onDelete != null) {
                  await onDelete!(context, post);
                }
              },
              itemBuilder: (ctx) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            )
          else
            const SizedBox(width: 40),
        ],
      ),
    );
  }
}

class _FeedCardFooter extends StatelessWidget {
  final TripFinalPost post;

  const _FeedCardFooter({required this.post});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: EngagementActionBar(
                entityType: post.engagementEntityType,
                entityId: post.id,
                likeCount: post.likeCount,
                commentCount: post.commentCount,
                shareCount: post.shareCount,
                hasLiked: post.hasLiked,
                onCommentTap: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (context) => CommentBottomSheet(
                      entityType: post.engagementEntityType,
                      entityId: post.id,
                    ),
                  );
                },
                onShareTap: () {
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: Colors.transparent,
                    builder: (context) => ShareBottomSheet(
                      entityType: post.engagementEntityType,
                      entityId: post.id,
                    ),
                  );
                },
                onLikeChanged: () {
                  final engagementProvider = context.read<EngagementProvider>();
                  final feedProvider = context.read<FeedProvider>();
                  final updatedPost = post.copyWith(
                    likeCount: engagementProvider.getLikeCount(post.id),
                    hasLiked: engagementProvider.isLiked(post.id),
                  );
                  final index = feedProvider.homeFeedPosts
                      .indexWhere((p) => p.id == post.id);
                  if (index >= 0) {
                    feedProvider.updatePost(index, updatedPost);
                  }
                },
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              if (post.isDirectPost) {
                context.push('/post/${post.engagementEntityType}/${post.id}');
              } else if ((post.tripId ?? '').isNotEmpty) {
                context.push(
                  '/trip/${post.tripId}',
                  extra: {'from': '/home'},
                );
              }
            },
            child: Text(post.isDirectPost ? 'View post' : 'Open trip'),
          ),
        ],
      ),
    );
  }
}

void _openTripMap(BuildContext context, TripFinalPost post) {
  if (post.isDirectPost || (post.tripId ?? '').isEmpty) {
    context.push('/post/${post.engagementEntityType}/${post.id}');
    return;
  }
  final pins = post.mapPins ?? const <FeedMapPin>[];
  final now = DateTime.now().toUtc();
  final places = <MapPlace>[
    for (var i = 0; i < pins.length; i++)
      MapPlace(
        place: Place(
          id: 'feed-pin-$i',
          name: (pins[i].name ?? '').trim().isEmpty
              ? 'Place ${i + 1}'
              : pins[i].name!,
          lat: pins[i].lat,
          lng: pins[i].lng,
          createdAt: now,
          updatedAt: now,
        ),
        origin: MapPlaceOrigin.threadEntry,
      ),
  ];
  context.push(
    '/trip/${post.tripId}/map',
    extra: {
      if (places.isNotEmpty) 'places': places,
    },
  );
}

void _openThreadEntry(
  BuildContext context, {
  required String? tripId,
  required String entryId,
}) {
  if ((tripId ?? '').isEmpty || entryId.isEmpty) return;
  context.push(
    '/trip/$tripId/thread',
    extra: {'highlightEntryId': entryId},
  );
}

class _PostcardBody extends StatefulWidget {
  final TripFinalPost post;

  const _PostcardBody({required this.post});

  @override
  State<_PostcardBody> createState() => _PostcardBodyState();
}

class _PostcardBodyState extends State<_PostcardBody> {
  int _photoIndex = 0;

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final media = post.curatedMedia;
    final placeLabel = (post.locationName ?? '').trim();
    final stamp = post.isDirectPost
        ? (placeLabel.isEmpty ? null : placeLabel)
        : ((post.trip?.destinations.isNotEmpty == true)
            ? post.trip!.destinations.first
            : (post.trip?.mood != null
                ? post.trip!.mood!.name.toUpperCase()
                : null));
    final route = post.isDirectPost
        ? placeLabel
        : formatFeedRoute(post.trip?.destinations);
    final pins = post.mapPins ?? const <FeedMapPin>[];
    final mapLabel = post.isDirectPost
        ? (placeLabel.isNotEmpty ? placeLabel : 'Place')
        : 'Route · ${pins.length} ${pins.length == 1 ? 'place' : 'places'}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 220,
              width: double.infinity,
              child: media.isEmpty
                  ? Container(
                      color: _mutedSurface(context),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.photo_outlined,
                        color: _mutedText(context),
                        size: 40,
                      ),
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        PageView.builder(
                          itemCount: media.length,
                          onPageChanged: (i) =>
                              setState(() => _photoIndex = i),
                          itemBuilder: (context, index) {
                            return Image.network(
                              buildOptimizedImageUrl(media[index], width: 1200),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: _mutedSurface(context),
                                alignment: Alignment.center,
                                child: const Icon(Icons.broken_image_outlined),
                              ),
                            );
                          },
                        ),
                        if (stamp != null && stamp.toString().trim().isNotEmpty)
                          Positioned(
                            top: 12,
                            right: 12,
                            child: Transform.rotate(
                              angle: 0.1,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _chipFill(context),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: _mutedText(context)
                                        .withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Text(
                                  stamp.toString(),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: _chipInk(context),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (media.length > 1)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 10,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(
                                media.length.clamp(0, 8),
                                (i) => Container(
                                  width: 6,
                                  height: 6,
                                  margin:
                                      const EdgeInsets.symmetric(horizontal: 2),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: i == _photoIndex
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: 0.45),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!post.isDirectPost &&
                  (post.trip?.title ?? '').trim().isNotEmpty)
                Text(
                  post.trip!.title,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              if (!post.isDirectPost && route.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  route,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        letterSpacing: 0.6,
                        color: _mutedText(context),
                      ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                post.summaryText,
                maxLines: post.isDirectPost ? 4 : 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: _panelInk(context),
                    ),
              ),
              // Trip recaps may pair AI summary with an author caption.
              // Direct posts use caption as summaryText — do not duplicate.
              if (!post.isDirectPost &&
                  (post.caption ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  post.caption!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _mutedText(context),
                        fontStyle: FontStyle.italic,
                      ),
                ),
              ],
            ],
          ),
        ),
        if (pins.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: _MapStrip(
              pins: pins,
              height: 88,
              label: mapLabel,
              onTap: () => _openTripMap(context, post),
            ),
          ),
        if (!post.isDirectPost && post.threadPreview.isNotEmpty)
          _ThreadPager(
            tripId: post.tripId,
            entries: post.threadPreview,
            entriesPerPage: 1,
          ),
      ],
    );
  }
}

class _MapFirstBody extends StatelessWidget {
  final TripFinalPost post;

  const _MapFirstBody({required this.post});

  @override
  Widget build(BuildContext context) {
    final pins = post.mapPins ?? const <FeedMapPin>[];
    final place = (post.locationName ?? '').trim();
    final route = post.isDirectPost
        ? place
        : formatFeedRoute(post.trip?.destinations);
    final media = post.curatedMedia;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (pins.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _MapStrip(
              pins: pins,
              height: 220,
              showOpenChip: !post.isDirectPost,
              label: post.isDirectPost && place.isNotEmpty ? place : null,
              routeScrim: !post.isDirectPost && route.isNotEmpty ? route : null,
              onTap: () => _openTripMap(context, post),
            ),
          )
        else if (route.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
            child: Text(
              route,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    letterSpacing: 0.6,
                    color: _mutedText(context),
                  ),
            ),
          ),
        if (media.isNotEmpty)
          SizedBox(
            height: 72,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              scrollDirection: Axis.horizontal,
              itemCount: media.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    buildOptimizedImageUrl(media[index], width: 240),
                    width: 96,
                    height: 72,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 96,
                      height: 72,
                      color: _mutedSurface(context),
                    ),
                  ),
                );
              },
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!post.isDirectPost &&
                  (post.trip?.title ?? '').trim().isNotEmpty)
                Text(
                  post.trip!.title,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              const SizedBox(height: 8),
              Text(
                post.summaryText,
                maxLines: post.isDirectPost ? 4 : 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: _panelInk(context),
                    ),
              ),
              if (!post.isDirectPost &&
                  (post.caption ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  post.caption!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _mutedText(context),
                        fontStyle: FontStyle.italic,
                      ),
                ),
              ],
            ],
          ),
        ),
        if (!post.isDirectPost && post.threadPreview.isNotEmpty)
          _ThreadPager(
            tripId: post.tripId,
            entries: post.threadPreview,
            entriesPerPage: 1,
          ),
      ],
    );
  }
}

class _ThreadReelBody extends StatefulWidget {
  final TripFinalPost post;

  const _ThreadReelBody({required this.post});

  @override
  State<_ThreadReelBody> createState() => _ThreadReelBodyState();
}

class _ThreadReelBodyState extends State<_ThreadReelBody> {
  late final PageController _controller;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final cover = post.coverMediaUrl ??
        (post.curatedMedia.isNotEmpty ? post.curatedMedia.first : null);
    final pins = post.mapPins ?? const <FeedMapPin>[];
    // Direct posts have no trip thread; use extra photos as visual “moments”.
    final entries = post.isDirectPost
        ? const <FeedThreadPreviewItem>[]
        : post.threadPreview;
    final photoMoments = post.isDirectPost
        ? post.curatedMedia.skip(1).take(4).toList()
        : const <String>[];
    final pages = <List<FeedThreadPreviewItem>>[];
    for (var i = 0; i < entries.length; i += 2) {
      pages.add(entries.skip(i).take(2).toList());
    }
    final pageCount = pages.isEmpty ? 1 : pages.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Size cover from the card width (not the viewport) so the
              // side-by-side reel stays visible on wide desktop browsers.
              final coverWidth =
                  (constraints.maxWidth * 0.42).clamp(120.0, 168.0);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: coverWidth,
                    height: 168,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: cover != null
                              ? Image.network(
                                  buildOptimizedImageUrl(cover, width: 600),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      Container(color: _mutedSurface(context)),
                                )
                              : Container(
                                  color: _mutedSurface(context),
                                  alignment: Alignment.center,
                                  child: const Icon(Icons.photo_outlined),
                                ),
                        ),
                        if (pins.isNotEmpty)
                          Positioned(
                            left: 8,
                            bottom: 8,
                            child: GestureDetector(
                              onTap: () => _openTripMap(context, post),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _chipFill(context),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: _mutedText(context)
                                        .withValues(alpha: 0.2),
                                  ),
                                ),
                                child: Text(
                                  post.isDirectPost &&
                                          (post.locationName ?? '')
                                              .trim()
                                              .isNotEmpty
                                      ? post.locationName!.trim()
                                      : '${pins.length} ${pins.length == 1 ? 'place' : 'places'}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.accent,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 168,
                      child: pages.isNotEmpty
                          ? PageView.builder(
                              controller: _controller,
                              onPageChanged: (i) =>
                                  setState(() => _page = i),
                              itemCount: pages.length,
                              itemBuilder: (context, pageIndex) {
                                final pageEntries = pages[pageIndex];
                                return Column(
                                  children: [
                                    for (var i = 0;
                                        i < pageEntries.length;
                                        i++) ...[
                                      if (i > 0) const SizedBox(height: 8),
                                      Expanded(
                                        child: _ReelSnippet(
                                          entry: pageEntries[i],
                                          tripId: post.tripId,
                                        ),
                                      ),
                                    ],
                                    if (pageEntries.length == 1)
                                      const Expanded(child: SizedBox()),
                                  ],
                                );
                              },
                            )
                          : photoMoments.isNotEmpty
                              ? Column(
                                  children: [
                                    for (var i = 0;
                                        i < photoMoments.take(2).length;
                                        i++) ...[
                                      if (i > 0) const SizedBox(height: 8),
                                      Expanded(
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          child: Image.network(
                                            buildOptimizedImageUrl(
                                              photoMoments[i],
                                              width: 400,
                                            ),
                                            width: double.infinity,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                Container(
                                              color: _mutedSurface(context),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                )
                              : Container(
                                  alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: _panel(context),
                                    borderRadius:
                                        const BorderRadius.horizontal(
                                      right: Radius.circular(10),
                                    ),
                                    border: const Border(
                                      left: BorderSide(
                                        color: AppTheme.accent,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    post.summaryText,
                                    maxLines: 6,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: _panelInk(context),
                                          height: 1.35,
                                        ),
                                  ),
                                ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!post.isDirectPost &&
                  (post.trip?.title ?? '').trim().isNotEmpty)
                Text(
                  post.trip!.title,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              const SizedBox(height: 6),
              Text(
                post.summaryText,
                maxLines: post.isDirectPost ? 3 : 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: _panelInk(context),
                    ),
              ),
            ],
          ),
        ),
        if (pages.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Row(
              children: [
                Text(
                  '${_page + 1} of $pageCount',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _mutedText(context),
                      ),
                ),
                const Spacer(),
                Row(
                  children: List.generate(pageCount, (i) {
                    return GestureDetector(
                      onTap: () {
                        _controller.animateToPage(
                          i,
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                        );
                      },
                      child: Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i == _page
                              ? AppTheme.accent
                              : _mutedText(context).withValues(alpha: 0.35),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ReelSnippet extends StatelessWidget {
  final FeedThreadPreviewItem entry;
  final String? tripId;

  const _ReelSnippet({
    required this.entry,
    required this.tripId,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openThreadEntry(
          context,
          tripId: tripId,
          entryId: entry.id,
        ),
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(10)),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          decoration: BoxDecoration(
            color: _panel(context),
            borderRadius:
                const BorderRadius.horizontal(right: Radius.circular(10)),
            border: const Border(
              left: BorderSide(color: AppTheme.accent, width: 2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  () {
                    final body = (entry.contentText ?? '').trim();
                    if (body.isNotEmpty) return body;
                    final place = (entry.placeName ?? '').trim();
                    if (place.isNotEmpty) return place;
                    return 'Thread entry';
                  }(),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _panelInk(context),
                        height: 1.35,
                      ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  if ((entry.placeName ?? '').trim().isNotEmpty) entry.placeName,
                  if (entry.likeCount > 0) '♥ ${entry.likeCount}',
                ].whereType<String>().join(' · '),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 10,
                      color: _mutedText(context),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapStrip extends StatelessWidget {
  final List<FeedMapPin> pins;
  final double height;
  final String? label;
  final String? routeScrim;
  final bool showOpenChip;
  final VoidCallback onTap;

  const _MapStrip({
    required this.pins,
    required this.height,
    required this.onTap,
    this.label,
    this.routeScrim,
    this.showOpenChip = false,
  });

  @override
  Widget build(BuildContext context) {
    final url = mapThumbnailUrlForPins(
      pins.map((p) => (lat: p.lat, lng: p.lng)).toList(),
      width: 640,
      height: height.round() * 2,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (url != null)
                  Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _mapFallback(context),
                  )
                else
                  _mapFallback(context),
                if (showOpenChip)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color:
                              _mutedText(context).withValues(alpha: 0.35),
                        ),
                      ),
                      child: const Text(
                        'Open map',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.accent,
                        ),
                      ),
                    ),
                  ),
                if (label != null)
                  Positioned(
                    left: 10,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _chipFill(context),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        label!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _chipInk(context),
                        ),
                      ),
                    ),
                  ),
                if (routeScrim != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 18, 12, 10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            _chipFill(context).withValues(alpha: 0),
                            _chipFill(context),
                          ],
                        ),
                      ),
                      child: Text(
                        routeScrim!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              letterSpacing: 0.6,
                              color: _mutedText(context),
                            ),
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

  Widget _mapFallback(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: AppTheme.feedMapWash(Theme.of(context).brightness),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.map_outlined,
        color: AppTheme.accent,
        size: 32,
      ),
    );
  }
}

class _ThreadPager extends StatefulWidget {
  final String? tripId;
  final List<FeedThreadPreviewItem> entries;
  final int entriesPerPage;

  const _ThreadPager({
    required this.tripId,
    required this.entries,
    required this.entriesPerPage,
  });

  @override
  State<_ThreadPager> createState() => _ThreadPagerState();
}

class _ThreadPagerState extends State<_ThreadPager> {
  late final PageController _controller;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <List<FeedThreadPreviewItem>>[];
    for (var i = 0; i < widget.entries.length; i += widget.entriesPerPage) {
      pages.add(
        widget.entries.skip(i).take(widget.entriesPerPage).toList(),
      );
    }
    if (pages.isEmpty) return const SizedBox.shrink();

    final rowHeight = 72.0;
    final height = widget.entriesPerPage == 1
        ? rowHeight
        : (rowHeight * widget.entriesPerPage) +
            (8.0 * (widget.entriesPerPage - 1));

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: height,
            child: PageView.builder(
              controller: _controller,
              onPageChanged: (i) => setState(() => _index = i),
              itemCount: pages.length,
              itemBuilder: (context, pageIndex) {
                final page = pages[pageIndex];
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < page.length; i++) ...[
                      if (i > 0) const SizedBox(height: 8),
                      SizedBox(
                        height: rowHeight,
                        child: _ThreadEntryRow(
                          entry: page[i],
                          tripId: widget.tripId,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
          if (pages.length > 1) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(pages.length, (i) {
                return Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == _index
                        ? AppTheme.accent
                        : _mutedText(context).withValues(alpha: 0.35),
                  ),
                );
              }),
            ),
          ],
        ],
      ),
    );
  }
}

class _ThreadEntryRow extends StatelessWidget {
  final FeedThreadPreviewItem entry;
  final String? tripId;

  const _ThreadEntryRow({
    required this.entry,
    required this.tripId,
  });

  @override
  Widget build(BuildContext context) {
    final text = (entry.contentText ?? '').trim();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openThreadEntry(
          context,
          tripId: tripId,
          entryId: entry.id,
        ),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _panel(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _mutedText(context).withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: entry.mediaUrl != null
                      ? Image.network(
                          buildOptimizedImageUrl(entry.mediaUrl!, width: 160),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _placeTile(context),
                        )
                      : _placeTile(context),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      text.isEmpty
                          ? (entry.placeName ?? 'Thread entry')
                          : text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: _panelInk(context),
                            height: 1.35,
                          ),
                    ),
                    if ((entry.placeName ?? '').trim().isNotEmpty &&
                        text.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        entry.placeName ?? '',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              color: _mutedText(context),
                            ),
                      ),
                    ],
                    if (entry.likeCount > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        '♥ ${entry.likeCount}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.likeRose,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeTile(BuildContext context) {
    final label = (entry.placeName ?? '').trim();
    return Container(
      color: _mutedSurface(context),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(4),
      child: Text(
        label.isEmpty ? '•' : label,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: _mutedText(context),
        ),
      ),
    );
  }
}
