import { EntityType } from '@prisma/client';
import { prisma } from '../prisma';

export class PermissionError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'PermissionError';
  }
}

export async function canViewEntity(
  userId: string | null,
  entityType: EntityType,
  entityId: string
): Promise<boolean> {
  if (entityType === 'TRIP_FINAL_POST') {
    const post = await prisma.tripFinalPost.findUnique({
      where: { id: entityId },
      select: {
        id: true,
        trip: {
          select: {
            userId: true,
            user: {
              select: {
                isPrivate: true,
              },
            },
          },
        },
      },
    });

    if (!post) return false;

    const owner = post.trip.user;
    if (!owner.isPrivate) return true;

    if (!userId) return false;

    if (userId === post.trip.userId) return true;

    const follow = await prisma.follow.findUnique({
      where: {
        followerId_followeeId: {
          followerId: userId,
          followeeId: post.trip.userId,
        },
      },
    });

    return !!follow;
  }

  if (entityType === 'TRIP_THREAD_ENTRY') {
    const entry = await prisma.tripThreadEntry.findUnique({
      where: { id: entityId },
      select: {
        id: true,
        trip: {
          select: {
            userId: true,
            user: {
              select: {
                isPrivate: true,
              },
            },
          },
        },
      },
    });

    if (!entry) return false;

    const owner = entry.trip.user;
    if (!owner.isPrivate) return true;

    if (!userId) return false;

    if (userId === entry.trip.userId) return true;

    const follow = await prisma.follow.findUnique({
      where: {
        followerId_followeeId: {
          followerId: userId,
          followeeId: entry.trip.userId,
        },
      },
    });

    return !!follow;
  }

  if (entityType === 'COMMENT') {
    const comment = await prisma.comment.findUnique({
      where: { id: entityId },
      select: {
        id: true,
        entityType: true,
        entityId: true,
      },
    });

    if (!comment) return false;

    return canViewEntity(userId, comment.entityType, comment.entityId);
  }

  return false;
}

export async function canLikeEntity(
  userId: string,
  entityType: EntityType,
  entityId: string
): Promise<boolean> {
  return canViewEntity(userId, entityType, entityId);
}

export async function canCommentOnEntity(
  userId: string,
  entityType: EntityType,
  entityId: string
): Promise<boolean> {
  return canViewEntity(userId, entityType, entityId);
}

export async function canEditComment(userId: string, commentId: string): Promise<boolean> {
  const comment = await prisma.comment.findUnique({
    where: { id: commentId },
    select: {
      userId: true,
      createdAt: true,
    },
  });

  if (!comment) return false;
  if (comment.userId !== userId) return false;

  const editWindowMs = 15 * 60 * 1000;
  const ageMs = Date.now() - comment.createdAt.getTime();

  return ageMs <= editWindowMs;
}

export async function canDeleteComment(userId: string, commentId: string): Promise<boolean> {
  const comment = await prisma.comment.findUnique({
    where: { id: commentId },
    select: {
      userId: true,
      entityType: true,
      entityId: true,
    },
  });

  if (!comment) return false;
  if (comment.userId === userId) return true;

  if (comment.entityType === 'TRIP_FINAL_POST') {
    const post = await prisma.tripFinalPost.findUnique({
      where: { id: comment.entityId },
      select: {
        trip: {
          select: {
            userId: true,
          },
        },
      },
    });

    return post?.trip.userId === userId;
  }

  if (comment.entityType === 'TRIP_THREAD_ENTRY') {
    const entry = await prisma.tripThreadEntry.findUnique({
      where: { id: comment.entityId },
      select: {
        trip: {
          select: {
            userId: true,
          },
        },
      },
    });

    return entry?.trip.userId === userId;
  }

  return false;
}

export async function canShareEntity(
  userId: string,
  entityType: EntityType,
  entityId: string
): Promise<boolean> {
  return canViewEntity(userId, entityType, entityId);
}

