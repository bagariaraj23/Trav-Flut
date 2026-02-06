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

async function getEntityOwner(
  entityType: EntityType,
  entityId: string
): Promise<string | null> {
  if (entityType === "TRIP_FINAL_POST") {
    const post = await prisma.tripFinalPost.findUnique({
      where: { id: entityId },
      select: { trip: { select: { userId: true } } },
    });
    return post?.trip?.userId || null;
  }
  if (entityType === "TRIP_THREAD_ENTRY") {
    const entry = await prisma.tripThreadEntry.findUnique({
      where: { id: entityId },
      select: { authorId: true },
    });
    return entry?.authorId || null;
  }
  return null;
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

  return await prisma.$transaction(async (tx) => {
    const comment = await tx.comment.create({
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

    return comment;
  });
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
    items: result.items.map((item) => ({
      ...item,
      replyCount: item._count.replies,
    })),
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

  return paginateResults(replies, limit);
}
