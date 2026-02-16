import { EntityType, Prisma } from "@prisma/client";
import { prisma } from "../prisma";
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
import { getEntityOwner, getPostFromComment, getTripIdFromEntry } from "../entity-owner";
import { createNotification } from "./notification";

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
      await invalidateEngagementCache(
        "comment",
        finalEntityType,
        finalEntityId
      );
    }

    return newComment;
  });

  // Fire-and-forget: create notifications without blocking response
  void (async () => {
    const contentPreview =
      sanitizedText.length > 60 ? sanitizedText.slice(0, 60) + "..." : sanitizedText;

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

    // 2. @Mention TAG notifications
    const mentionUsernames = extractMentions(sanitizedText);
    if (mentionUsernames.length > 0) {
      try {
        const postInfo = await getPostFromComment(comment.id);
        if (!postInfo) return;

        const users = await prisma.user.findMany({
          where: {
            deletedAt: null,
            OR: mentionUsernames.map((u) => ({
              username: { equals: u, mode: "insensitive" as const },
            })),
          },
          select: { id: true },
        });

        const contentPreviewShort =
          sanitizedText.length > 60 ? sanitizedText.slice(0, 60) + "..." : sanitizedText;
        let tripId: string | null = null;
        if (postInfo.entityType === "TRIP_THREAD_ENTRY") {
          tripId = await getTripIdFromEntry(postInfo.entityId);
        }

        for (const u of users) {
          if (u.id === userId) continue;
          try {
            await createNotification({
              type: "TAG",
              actorId: userId,
              recipientId: u.id,
              entityType: "COMMENT",
              entityId: comment.id,
              metadata: {
                contentPreview: contentPreviewShort,
                postEntityType: postInfo.entityType,
                postEntityId: postInfo.entityId,
                commentId: comment.id,
                ...(tripId && { tripId }),
              },
            });
          } catch (tagErr) {
            console.error(
              "[Notification] Failed to create TAG notification for mention:",
              { commentId: comment.id, mentionedUserId: u.id, error: tagErr }
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
    select: { userId: true },
  });

  if (!comment) {
    throw new Error("Comment not found");
  }

  if (comment.userId !== userId) {
    throw new Error("Unauthorized");
  }

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
  return await prisma.$transaction(async (tx) => {
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
      await tx.comment.deleteMany({
        where: { id: { in: replyIds } },
      });
    }

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
      await invalidateEngagementCache(
        "comment",
        comment.entityType,
        comment.entityId
      );
    }

    return { deleted: true, replyCount: replyIds.length };
  });
}

export async function getCommentsByEntity(
  entityType: EntityType,
  entityId: string,
  cursor?: string,
  limit: number = ENGAGEMENT_CONSTANTS.PAGINATION.DEFAULT_LIMIT
) {
  const where: any = {
    entityType,
    entityId,
    parentCommentId: null,
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

  return {
    ...result,
    items: result.items.map((item: any) => {
      const { _count: c, ...comment } = item;
      return {
        ...comment,
        replyCount: c.replies,
        likeCount: comment.likeCount ?? 0,
      };
    }),
  };
}

export async function getCommentReplies(
  commentId: string,
  cursor?: string,
  limit: number = ENGAGEMENT_CONSTANTS.PAGINATION.DEFAULT_LIMIT
) {
  const where: any = {
    parentCommentId: commentId,
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
