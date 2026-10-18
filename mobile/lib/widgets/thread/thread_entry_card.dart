import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tripthread/models/trip.dart';
import 'package:tripthread/utils/app_theme.dart';
import 'package:tripthread/widgets/engagement/engagement_action_bar.dart';
import 'package:tripthread/widgets/mention_text.dart';
import 'package:tripthread/widgets/sheets/comment_bottom_sheet.dart';
import 'package:tripthread/widgets/sheets/share_bottom_sheet.dart';

class ThreadEntryCard extends StatelessWidget {
  final TripThreadEntry entry;
  final bool isLast;
  final bool showRail;
  final bool canModerate;
  final VoidCallback? onOpenActions;
  final VoidCallback onReply;
  final Widget? media;
  final Map<String, String> usernameToUserId;

  const ThreadEntryCard({
    super.key,
    required this.entry,
    required this.isLast,
    required this.showRail,
    required this.canModerate,
    required this.onReply,
    this.onOpenActions,
    this.media,
    this.usernameToUserId = const {},
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locationLabel = entry.place?.name ?? entry.locationName;
    final hasPlace = entry.place != null ||
        entry.locationName != null ||
        entry.type == ThreadEntryType.location ||
        entry.type == ThreadEntryType.checkin;

    return Dismissible(
      key: ValueKey('entry-reply-${entry.id}'),
      direction: DismissDirection.startToEnd,
      background: _replyBackground(context),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onReply();
        }
        return false;
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showRail) ...[
                _TypeRail(type: entry.type, isLast: isLast),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: GestureDetector(
                  onLongPress: canModerate ? onOpenActions : null,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onTap: () => context.push('/profile/${entry.authorId}'),
                              child: CircleAvatar(
                                radius: 16,
                                backgroundColor: AppTheme.muted,
                                backgroundImage: entry.author.avatarUrl != null
                                    ? NetworkImage(entry.author.avatarUrl!)
                                    : null,
                                child: entry.author.avatarUrl == null
                                    ? Text(
                                        (entry.author.name != null &&
                                                entry.author.name!.isNotEmpty)
                                            ? entry.author.name!
                                                .substring(0, 1)
                                                .toUpperCase()
                                            : 'U',
                                        style: const TextStyle(
                                          color: AppTheme.ink,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      )
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  GestureDetector(
                                    onTap: () =>
                                        context.push('/profile/${entry.authorId}'),
                                    child: Text(
                                      entry.author.name ?? 'User',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: scheme.onSurface,
                                          ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _metaLine(locationLabel),
                                    style: Theme.of(context).textTheme.bodySmall,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            if (!showRail) ...[
                              const SizedBox(width: 6),
                              Icon(_typeIcon(entry.type), size: 16, color: AppTheme.accent),
                            ],
                            if (canModerate)
                              IconButton(
                                onPressed: onOpenActions,
                                icon: Icon(
                                  Icons.more_horiz,
                                  size: 20,
                                  color: scheme.onSurfaceVariant,
                                ),
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 32,
                                ),
                              ),
                          ],
                        ),
                        if (entry.contentText != null &&
                            entry.contentText!.trim().isNotEmpty) ...[
                          const SizedBox(height: 12),
                          MentionText(
                            text: entry.contentText!,
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  color: scheme.onSurface,
                                  height: 1.45,
                                ),
                            usernameToUserId: usernameToUserId,
                          ),
                        ],
                        if (media != null) media!,
                        if (hasPlace && (locationLabel != null || entry.place != null))
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Material(
                                color: AppTheme.accentSoft,
                                borderRadius: BorderRadius.circular(999),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(999),
                                  onTap: entry.place == null
                                      ? null
                                      : () {
                                          context.push(
                                            '/trip/${entry.tripId}/map',
                                            extra: {
                                              'tripTitle': 'Trip Map',
                                              'initialZoomLocation': entry.place,
                                            },
                                          );
                                        },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          entry.type == ThreadEntryType.checkin
                                              ? Icons.near_me
                                              : Icons.place_outlined,
                                          size: 14,
                                          color: AppTheme.accent,
                                        ),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            locationLabel ?? 'Location',
                                            style: const TextStyle(
                                              color: AppTheme.accent,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        Divider(height: 1, color: scheme.outlineVariant),
                        const SizedBox(height: 8),
                        EngagementActionBar(
                          entityType: 'TRIP_THREAD_ENTRY',
                          entityId: entry.id,
                          likeCount: entry.likeCount,
                          commentCount: entry.commentCount,
                          hasLiked: entry.hasLiked,
                          onCommentTap: () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (context) => CommentBottomSheet(
                                entityType: 'TRIP_THREAD_ENTRY',
                                entityId: entry.id,
                              ),
                            );
                          },
                          onShareTap: () {
                            showModalBottomSheet(
                              context: context,
                              backgroundColor: Colors.transparent,
                              builder: (context) => ShareBottomSheet(
                                entityType: 'TRIP_THREAD_ENTRY',
                                entityId: entry.id,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _metaLine(String? locationLabel) {
    final when = DateFormat('MMM d, h:mm a').format(entry.createdAt.toLocal());
    if (locationLabel != null && locationLabel.isNotEmpty) {
      return '$when · $locationLabel';
    }
    return when;
  }

  Widget _replyBackground(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: AppTheme.accentSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.reply, color: AppTheme.accent, size: 20),
          SizedBox(width: 8),
          Text(
            'Reply',
            style: TextStyle(
              color: AppTheme.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeRail extends StatelessWidget {
  final ThreadEntryType type;
  final bool isLast;

  const _TypeRail({required this.type, required this.isLast});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: AppTheme.accent,
              shape: BoxShape.circle,
            ),
            child: Icon(_typeIcon(type), color: Colors.white, size: 18),
          ),
          if (!isLast)
            Expanded(
              child: Container(
                width: 1,
                margin: const EdgeInsets.symmetric(vertical: 6),
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
        ],
      ),
    );
  }
}

IconData _typeIcon(ThreadEntryType type) {
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
