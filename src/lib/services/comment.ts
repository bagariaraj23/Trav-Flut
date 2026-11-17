import { EntityType, Prisma, UserSafetyAction } from "@prisma/client";
import { prisma } from "../prisma";
import { ValidationError } from "../errors";
import { sanitizeInput } from "../security";
import {
  validateEntityExists,
  invalidateEngagementCache,
  incrementEntityCount,
  decrementEntityCount,
  paginateResults,
  USER_PUBLIC_SELECT,
  USER_MINIMAL_SELECT,
  ENGAGEMENT_CONSTANTS,
} from "./engagement-utils";
import { getEntityOwner, getPostFromComment, getTripIdFromEntry, getTripTitle } from "../entity-owner";
import { canViewEntity } from "../auth/permissions";
import { blockedUserIds } from "./userSafety";
import { createNotification } from "./notification";
import {
  loadTripForTagging,
  parseTripScopedMentions,
  resolveRecipientIdsForTripMentions,
} from "./tripTagResolution";

/** Extract @username mentions from text (case-insensitive, unique). */
function extractMentions(text: string): string[] {
  const regex = /@([a-zA-Z0-9_.]+)/g;
  const seen = new Set<string>();
  const result: string[] = [];
  let m: RegExpExecArray | null;
  while ((m = regex.exec(text)) !== null) {
    const username = m[1].toLowerCase();
    if (!seen.has(username)) {
      seen.add(username);
      result.push(m[1]);
    }
  }
  return result;
}

const CANNOT_MENTION = "You can't mention this person";

async function finalPostAuthorId(entityId: string): Promise<string | null> {
  const post = await prisma.tripFinalPost.findUnique({
    where: { id: entityId },
    select: { userId: true },
  });
  return post?.userId ?? null;
}

async function restrictedTargetIds(actorId: string): Promise<Set<string>> {
  const rows = await prisma.userSafetyRelation.findMany({
    where: { actorId, action: UserSafetyAction.RESTRICT },
    select: { targetId: true },
  });
  return new Set(rows.map((row) => row.targetId));
}

/** A final-post comment cannot @mention someone who has restricted the author of the comment. */
async function assertFinalPostMentionsAllowed(
  commenterId: string,
  entityType: EntityType,
  text: string
) {
  if (entityType !== EntityType.TRIP_FINAL_POST) return;
  const names = extractMentions(text);
  if (names.length === 0) return;
  const users = await prisma.user.findMany({
    where: {
      deletedAt: null,
      OR: names.map((name) => ({
        username: { equals: name, mode: "insensitive" as const },
      })),
    },
    select: { id: true },
  });
  if (users.length === 0) return;
  const restricted = await prisma.userSafetyRelation.findFirst({
    where: {
      action: UserSafetyAction.RESTRICT,
      targetId: commenterId,
      actorId: { in: users.map((user) => user.id) },
    },
    select: { id: true },
  });
  if (restricted) throw new ValidationError(CANNOT_MENTION);
}

function audienceFilter(options: {
  hiddenIds: string[];
  quietIds: Set<string>;
  viewerId?: string | null;
  authorId: string | null;
}): Prisma.CommentWhereInput {
  const parts: Prisma.CommentWhereInput[] = [];
  if (options.hiddenIds.length > 0) {
    parts.push({ userId: { notIn: options.hiddenIds } });
  }
  const concealQuiet =
    !!options.authorId &&
    options.viewerId !== options.authorId &&
    options.quietIds.size > 0;
  if (concealQuiet) {
    const quiet = [...options.quietIds];
    parts.push({
      OR: [
        { userId: { notIn: quiet } },
        ...(options.viewerId ? [{ userId: options.viewerId }] : []),
      ],
    });
  }
  if (parts.length === 0) return {};
  if (parts.length === 1) return parts[0];
  return { AND: parts };
}

/**
 * Top-level final-post comment totals for this viewer.
 * The post author sees every comment. A restricted commenter sees public
 * comments plus their own. Everyone else sees the public comments only.
 */
export async function visibleFinalPostCommentCounts(
  posts: { id: string; userId: string }[],
  viewerId: string | null
): Promise<Map<string, number>> {
  const totals = new Map<string, number>();
  if (posts.length === 0) return totals;
  const authorByPost = new Map(posts.map((post) => [post.id, post.userId]));
  const authors = [...new Set(posts.map((post) => post.userId))];
  const relations = await prisma.userSafetyRelation.findMany({
    where: { action: UserSafetyAction.RESTRICT, actorId: { in: authors } },
    select: { actorId: true, targetId: true },
  });
  const quietByAuthor = new Map<string, Set<string>>();
  for (const row of relations) {
    const set = quietByAuthor.get(row.actorId) ?? new Set<string>();
    set.add(row.targetId);
    quietByAuthor.set(row.actorId, set);
  }
  const grouped = await prisma.comment.groupBy({
    by: ["entityId", "userId"],
    where: {
      entityType: EntityType.TRIP_FINAL_POST,
      parentCommentId: null,
      entityId: { in: posts.map((post) => post.id) },
    },
    _count: { _all: true },
  });
  for (const post of posts) totals.set(post.id, 0);
  for (const row of grouped) {
    const authorId = authorByPost.get(row.entityId);
    const quiet = authorId ? quietByAuthor.get(authorId) : undefined;
    const concealed =
      !!quiet?.has(row.userId) &&
      viewerId !== authorId &&
      viewerId !== row.userId;
    if (concealed) continue;
    totals.set(row.entityId, (totals.get(row.entityId) ?? 0) + row._count._all);
  }
  return totals;
}

async function validateParentComment(
  commentId: string
): Promise<{ entityType: EntityType; entityId: string } | null> {
  const parent = await prisma.comment.findUnique({
    where: { id: commentId },
    select: {
      id: true,
      entityType: true,
      entityId: true,
      parentCommentId: true,
    },
  });
  if (!parent) {
    return null;
  }
  if (parent.parentCommentId) {
    throw new Error("Nesting limited to one level only");
  }
  return { entityType: parent.entityType, entityId: parent.entityId };
}

export async function createComment(
  userId: string,
  entityType: EntityType,
  entityId: string,
  contentText: string,
  parentCommentId?: string
) {
  if (
    contentText.length < ENGAGEMENT_CONSTANTS.COMMENT.MIN_LENGTH ||
    contentText.length > ENGAGEMENT_CONSTANTS.COMMENT.MAX_LENGTH
  ) {
    throw new Error(
      `Comment must be between ${ENGAGEMENT_CONSTANTS.COMMENT.MIN_LENGTH} and ${ENGAGEMENT_CONSTANTS.COMMENT.MAX_LENGTH} characters`
    );
  }

  const sanitizedText = sanitizeInput(contentText);
  if (sanitizedText.trim().length === 0) {
    throw new Error("Comment content is required");
  }

  let finalEntityType = entityType;
  let finalEntityId = entityId;

  if (parentCommentId) {
    const parentInfo = await validateParentComment(parentCommentId);
    if (!parentInfo) {
      throw new Error("Parent comment not found");
    }
    finalEntityType = parentInfo.entityType;
    finalEntityId = parentInfo.entityId;
  } else {
    const exists = await validateEntityExists(entityType, entityId);
    if (!exists) {
      throw new Error("Entity not found");
    }
  }

  await assertFinalPostMentionsAllowed(userId, finalEntityType, sanitizedText);
  const finalPostAuthor =
    finalEntityType === EntityType.TRIP_FINAL_POST
      ? await finalPostAuthorId(finalEntityId)
      : null;
  const commentIsQuiet =
    !!finalPostAuthor &&
    (await restrictedTargetIds(finalPostAuthor)).has(userId);

  const comment = await prisma.$transaction(async (tx) => {
    const newComment = await tx.comment.create({
      data: {
        userId,
        entityType: finalEntityType,
        entityId: finalEntityId,
        contentText: sanitizedText,
        parentCommentId: parentCommentId || null,
      },
      include: {
        user: {
          select: USER_PUBLIC_SELECT,
        },
      },
    });

    if (!parentCommentId) {
      await incrementEntityCount(
        finalEntityType,
        finalEntityId,
        "commentCount",
        tx
      );
    }

    return newComment;
  });

  if (!parentCommentId) {
    await invalidateEngagementCache(
      "comment",
      finalEntityType,
      finalEntityId
    );
  }

  // Fire-and-forget: create notifications without blocking response
  void (async () => {
    const contentPreview =
      sanitizedText.length > 60 ? sanitizedText.slice(0, 60) + "..." : sanitizedText;
    const threadTripId =
      finalEntityType === "TRIP_THREAD_ENTRY"
        ? await getTripIdFromEntry(finalEntityId)
        : null;
    const tripName =
      threadTripId != null ? await getTripTitle(threadTripId) : null;

    // 1. Comment / Reply notification
    try {
      let recipientId: string | null;
      let notifType: "COMMENT" | "COMMENT_REPLY";

      if (parentCommentId) {
        const parent = await prisma.comment.findUnique({
          where: { id: parentCommentId },
          select: { userId: true },
        });
        recipientId = parent?.userId ?? null;
        notifType = "COMMENT_REPLY";
      } else {
        recipientId = await getEntityOwner(finalEntityType, finalEntityId);
        notifType = "COMMENT";
      }

      if (recipientId) {
        await createNotification({
          type: notifType,
          actorId: userId,
          recipientId,
          entityType: finalEntityType,
          entityId: finalEntityId,
          metadata: {
            contentPreview,
            commentId: comment.id,
            ...(parentCommentId && { parentCommentId }),
            ...(threadTripId && { tripId: threadTripId }),
            ...(tripName && { tripName }),
            ...(finalEntityType === "TRIP_THREAD_ENTRY" && {
              threadEntryId: finalEntityId,
            }),
          },
        });
      }
    } catch (err) {
      console.error(
        "[Notification] Failed to create COMMENT/REPLY notification:",
        {
          entityType: finalEntityType,
          entityId: finalEntityId,
          actorId: userId,
          error: err,
        }
      );
    }

    // 2. @Mention TAG notifications. A quiet final-post comment is visible
    // only to its author and the post author, so it does not notify anyone else.
    const mentionUsernames = extractMentions(sanitizedText);
    if (!commentIsQuiet && mentionUsernames.length > 0) {
      try {
        const postInfo = await getPostFromComment(comment.id);
        if (!postInfo) return;

        const contentPreviewShort =
          sanitizedText.length > 60 ? sanitizedText.slice(0, 60) + "..." : sanitizedText;
        let tripId: string | null = null;
        if (postInfo.entityType === "TRIP_THREAD_ENTRY") {
          tripId = await getTripIdFromEntry(postInfo.entityId);
        } else if (postInfo.entityType === "TRIP_FINAL_POST") {
          const fp = await prisma.tripFinalPost.findUnique({
            where: { id: postInfo.entityId },
            select: { tripId: true },
          });
          tripId = fp?.tripId ?? null;
        }

        const recipientSet = new Set<string>();

        if (
          tripId &&
          (postInfo.entityType === "TRIP_THREAD_ENTRY" ||
            postInfo.entityType === "TRIP_FINAL_POST")
        ) {
          const trip = await loadTripForTagging(tripId);
          if (trip) {
            const { wantsAll, specificLower } = parseTripScopedMentions(mentionUsernames);
            const fromTrip = await resolveRecipientIdsForTripMentions({
              trip: { userId: trip.userId, participants: trip.participants },
              actorId: userId,
              wantsAll,
              specificLower,
            });
            for (const id of fromTrip) recipientSet.add(id);
          }
        }

        const globalUsers = await prisma.user.findMany({
          where: {
            deletedAt: null,
            OR: mentionUsernames.map((u) => ({
              username: { equals: u, mode: "insensitive" as const },
            })),
          },
          select: { id: true },
        });
        for (const u of globalUsers) {
          if (u.id === userId) continue;
          const canRecipientView = await canViewEntity(
            u.id,
            postInfo.entityType,
            postInfo.entityId
          );
          if (!canRecipientView) continue;
          recipientSet.add(u.id);
        }

        const recipientIds = Array.from(recipientSet);

        const tripNameMeta =
          tripId != null ? await getTripTitle(tripId) : null;

        for (const recipientId of recipientIds) {
          if (recipientId === userId) continue;
          try {
            await createNotification({
              type: "TAG",
              actorId: userId,
              recipientId,
              entityType: "COMMENT",
              entityId: comment.id,
              metadata: {
                tagSource: "comment",
                contentPreview: contentPreviewShort,
                postEntityType: postInfo.entityType,
                postEntityId: postInfo.entityId,
                commentId: comment.id,
                ...(tripId && { tripId }),
                ...(tripNameMeta && { tripName: tripNameMeta }),
                ...(postInfo.entityType === "TRIP_THREAD_ENTRY" && {
                  threadEntryId: postInfo.entityId,
                }),
                ...(postInfo.entityType === "TRIP_FINAL_POST" && {
                  tripFinalPostId: postInfo.entityId,
                }),
              },
            });
          } catch (tagErr) {
            console.error(
              "[Notification] Failed to create TAG notification for mention:",
              { commentId: comment.id, mentionedUserId: recipientId, error: tagErr }
            );
          }
        }
      } catch (err) {
        console.error(
          "[Notification] Failed to process @mentions:",
          { commentId: comment.id, error: err }
        );
      }
    }
  })();

  return comment;
}

export async function updateComment(
  userId: string,
  commentId: string,
  newText: string
) {
  if (
    newText.length < ENGAGEMENT_CONSTANTS.COMMENT.MIN_LENGTH ||
    newText.length > ENGAGEMENT_CONSTANTS.COMMENT.MAX_LENGTH
  ) {
    throw new Error(
      `Comment must be between ${ENGAGEMENT_CONSTANTS.COMMENT.MIN_LENGTH} and ${ENGAGEMENT_CONSTANTS.COMMENT.MAX_LENGTH} characters`
    );
  }

  const sanitizedText = sanitizeInput(newText);
  if (sanitizedText.trim().length === 0) {
    throw new Error("Comment content is required");
  }

  const comment = await prisma.comment.findUnique({
    where: { id: commentId },
    select: { userId: true, entityType: true, entityId: true },
  });

  if (!comment) {
    throw new Error("Comment not found");
  }

  if (comment.userId !== userId) {
    throw new Error("Unauthorized");
  }

  await assertFinalPostMentionsAllowed(
    userId,
    comment.entityType,
    sanitizedText
  );

  return await prisma.comment.update({
    where: { id: commentId },
    data: {
      contentText: sanitizedText,
      updatedAt: new Date(),
    },
    include: {
      user: {
        select: USER_PUBLIC_SELECT,
      },
    },
  });
}

export async function deleteComment(userId: string, commentId: string) {
  const result = await prisma.$transaction(async (tx) => {
    const comment = await tx.comment.findUnique({
      where: { id: commentId },
      include: {
        replies: {
          select: { id: true },
        },
      },
    });

    if (!comment) {
      throw new Error("Comment not found");
    }

    const entityOwner = await getEntityOwner(
      comment.entityType,
      comment.entityId
    );
    const isAuthor = comment.userId === userId;
    const isEntityOwner = entityOwner === userId;

    if (!isAuthor && !isEntityOwner) {
      throw new Error("Unauthorized");
    }

    const replyIds = comment.replies.map((r) => r.id);
    if (replyIds.length > 0) {
      // Delete likes on replies
      await tx.like.deleteMany({
        where: {
          entityType: EntityType.COMMENT,
          entityId: { in: replyIds },
        },
      });
      await tx.comment.deleteMany({
        where: { id: { in: replyIds } },
      });
    }

    // Delete likes on comment itself
    await tx.like.deleteMany({
      where: {
        entityType: EntityType.COMMENT,
        entityId: commentId,
      },
    });

    await tx.comment.delete({
      where: { id: commentId },
    });

    if (!comment.parentCommentId) {
      await decrementEntityCount(
        comment.entityType,
        comment.entityId,
        "commentCount",
        tx
      );
    }

    return {
      deleted: true,
      replyCount: replyIds.length,
      invalidatedEntity:
        !comment.parentCommentId
          ? {
              entityType: comment.entityType,
              entityId: comment.entityId,
            }
          : null,
    };
  });

  if (result.invalidatedEntity) {
    await invalidateEngagementCache(
      "comment",
      result.invalidatedEntity.entityType,
      result.invalidatedEntity.entityId
    );
  }

  return { deleted: result.deleted, replyCount: result.replyCount };
}

export async function getCommentsByEntity(
  entityType: EntityType,
  entityId: string,
  cursor?: string,
  limit: number = ENGAGEMENT_CONSTANTS.PAGINATION.DEFAULT_LIMIT,
  viewerId?: string | null
) {
  const hiddenIds = viewerId ? await blockedUserIds(viewerId) : [];
  const authorId =
    entityType === EntityType.TRIP_FINAL_POST
      ? await finalPostAuthorId(entityId)
      : null;
  const quietIds = authorId ? await restrictedTargetIds(authorId) : new Set<string>();
  const where: any = {
    entityType,
    entityId,
    parentCommentId: null,
    ...audienceFilter({ hiddenIds, quietIds, viewerId, authorId }),
  };

  if (cursor) {
    where.id = { lt: cursor };
  }

  const comments = await prisma.comment.findMany({
    where,
    take: limit + 1,
    orderBy: { createdAt: "desc" },
    select: {
      id: true,
      userId: true,
      entityType: true,
      entityId: true,
      contentText: true,
      parentCommentId: true,
      likeCount: true,
      createdAt: true,
      updatedAt: true,
      user: {
        select: USER_PUBLIC_SELECT,
      },
      _count: {
        select: {
          replies: true,
        },
      },
    },
  });

  const result = paginateResults(comments, limit);
  const replyCounts = await visibleReplyCounts(
    result.items.map((item: { id: string }) => item.id),
    viewerId,
    authorId,
    quietIds
  );

  return {
    ...result,
    items: result.items.map((item: any) => {
      const { _count: c, ...comment } = item;
      return {
        ...comment,
        replyCount: replyCounts.get(comment.id) ?? c.replies,
        likeCount: comment.likeCount ?? 0,
      };
    }),
  };
}

async function visibleReplyCounts(
  parentIds: string[],
  viewerId: string | null | undefined,
  authorId: string | null,
  quietIds: Set<string>
): Promise<Map<string, number>> {
  const counts = new Map<string, number>();
  if (parentIds.length === 0 || !authorId || quietIds.size === 0) return counts;
  const grouped = await prisma.comment.groupBy({
    by: ["parentCommentId", "userId"],
    where: { parentCommentId: { in: parentIds } },
    _count: { _all: true },
  });
  for (const row of grouped) {
    if (!row.parentCommentId) continue;
    const concealed =
      quietIds.has(row.userId) &&
      viewerId !== authorId &&
      viewerId !== row.userId;
    if (concealed) continue;
    counts.set(
      row.parentCommentId,
      (counts.get(row.parentCommentId) ?? 0) + row._count._all
    );
  }
  for (const id of parentIds) {
    if (!counts.has(id)) counts.set(id, 0);
  }
  return counts;
}

export async function getCommentReplies(
  commentId: string,
  cursor?: string,
  limit: number = ENGAGEMENT_CONSTANTS.PAGINATION.DEFAULT_LIMIT,
  viewerId?: string | null
) {
  const hiddenIds = viewerId ? await blockedUserIds(viewerId) : [];
  const parent = await prisma.comment.findUnique({
    where: { id: commentId },
    select: { entityType: true, entityId: true },
  });
  const authorId =
    parent?.entityType === EntityType.TRIP_FINAL_POST
      ? await finalPostAuthorId(parent.entityId)
      : null;
  const quietIds = authorId ? await restrictedTargetIds(authorId) : new Set<string>();
  const where: any = {
    parentCommentId: commentId,
    ...audienceFilter({ hiddenIds, quietIds, viewerId, authorId }),
  };

  if (cursor) {
    where.id = { lt: cursor };
  }

  const replies = await prisma.comment.findMany({
    where,
    take: limit + 1,
    orderBy: { createdAt: "desc" },
    select: {
      id: true,
      userId: true,
      entityType: true,
      entityId: true,
      contentText: true,
      parentCommentId: true,
      likeCount: true,
      createdAt: true,
      updatedAt: true,
      user: {
        select: USER_PUBLIC_SELECT,
      },
    },
  });

  const result = paginateResults(replies, limit);
  return {
    ...result,
    items: result.items.map((item: any) => ({
      ...item,
      likeCount: item.likeCount ?? 0,
    })),
  };
}
