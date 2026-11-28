import { EntityType, Prisma } from "@prisma/client";
import { prisma, type PrismaTransactionClient } from "../prisma";
import {
  AuthorizationError,
  NotFoundError,
  ValidationError,
} from "../errors";
import { canViewEntity } from "../auth/permissions";
import { checkLikeStatus } from "./like";
import { assertAuthorUploads, MAX_POST_MEDIA } from "./postMedia";

const CAPTION_MAX = 2000;
const LOCATION_MAX = 200;

const userSelect = {
  id: true,
  email: true,
  username: true,
  name: true,
  avatarUrl: true,
  bio: true,
  isPrivate: true,
  createdAt: true,
  updatedAt: true,
} as const;

export type DirectPostInput = {
  caption: string;
  media?: string[];
  locationName?: string | null;
  latitude?: number | null;
  longitude?: number | null;
  placeId?: string | null;
  /** When false, creates/keeps an unpublished draft (not on the home feed). */
  isPublished?: boolean;
};

type UserPostRow = Prisma.UserPostGetPayload<{ include: { user: { select: typeof userSelect } } }>;

export class UserPostService {
  static async create(userId: string, input: DirectPostInput) {
    const data = await normalize(prisma, userId, input);
    const publish = input.isPublished !== false;
    const now = new Date();
    const post = await prisma.userPost.create({
      data: {
        userId,
        ...data,
        isPublished: publish,
        publishedAt: publish ? now : null,
      },
      include: { user: { select: userSelect } },
    });
    return toHomeFeedItem(post, false);
  }

  static async update(postId: string, userId: string, input: DirectPostInput) {
    const existing = await prisma.userPost.findUnique({
      where: { id: postId },
      select: { userId: true, isPublished: true, publishedAt: true },
    });
    if (!existing) throw new NotFoundError("Post not found");
    if (existing.userId !== userId) {
      throw new AuthorizationError("You can only edit your own post");
    }

    const data = await normalize(prisma, userId, input);
    const publish =
      input.isPublished === undefined
        ? existing.isPublished
        : input.isPublished;
    const now = new Date();
    const post = await prisma.userPost.update({
      where: { id: postId },
      data: {
        ...data,
        isPublished: publish,
        publishedAt: publish
          ? existing.publishedAt ?? now
          : existing.isPublished
            ? existing.publishedAt
            : null,
      },
      include: { user: { select: userSelect } },
    });
    const liked = await checkLikeStatus(userId, EntityType.USER_POST, [post.id]);
    return toHomeFeedItem(post, liked[post.id] || false);
  }

  /** Owner can load an unpublished draft for edit/preview. */
  static async getOwn(postId: string, userId: string) {
    const post = await prisma.userPost.findUnique({
      where: { id: postId },
      include: { user: { select: userSelect } },
    });
    if (!post) throw new NotFoundError("Post not found");
    if (post.userId !== userId) {
      throw new AuthorizationError("You can only open your own draft");
    }
    return toHomeFeedItem(post, false);
  }

  static async remove(postId: string, userId: string) {
    const existing = await prisma.userPost.findUnique({
      where: { id: postId },
      select: { userId: true },
    });
    if (!existing) throw new NotFoundError("Post not found");
    if (existing.userId !== userId) {
      throw new AuthorizationError("You can only delete your own post");
    }

    await prisma.$transaction(async (tx) => {
      await deleteEngagement(tx, postId);
      await tx.userPost.delete({ where: { id: postId } });
    });
  }

  static async getVisible(postId: string, viewerId: string) {
    const post = await prisma.userPost.findUnique({
      where: { id: postId },
      include: { user: { select: userSelect } },
    });
    if (!post || !post.isPublished) throw new NotFoundError("Post not found");
    const allowed = await canViewEntity(viewerId, EntityType.USER_POST, postId);
    if (!allowed) throw new NotFoundError("Post not found");
    const liked = await checkLikeStatus(viewerId, EntityType.USER_POST, [post.id]);
    return toHomeFeedItem(post, liked[post.id] || false);
  }
}

export function directPostAudience(
  viewerId: string,
  followedUserIds: string[],
  hiddenUserIds: string[]
): Prisma.UserPostWhereInput {
  return {
    isPublished: true,
    ...(hiddenUserIds.length > 0 ? { userId: { notIn: hiddenUserIds } } : {}),
    OR: [
      { userId: viewerId },
      ...(followedUserIds.length > 0
        ? [{ userId: { in: followedUserIds } }]
        : []),
      { user: { isPrivate: false } },
    ],
  };
}

export async function loadDirectPostsForFeed(args: {
  where: Prisma.UserPostWhereInput;
  cursor: { createdAt: Date; id: string } | null;
  offset: number;
  limit: number;
  viewerId: string;
}) {
  const where: Prisma.UserPostWhereInput = args.cursor
    ? {
        AND: [
          args.where,
          {
            OR: [
              { createdAt: { lt: args.cursor.createdAt } },
              {
                AND: [
                  { createdAt: args.cursor.createdAt },
                  { id: { lt: args.cursor.id } },
                ],
              },
            ],
          },
        ],
      }
    : args.where;

  const rows = await prisma.userPost.findMany({
    where,
    include: { user: { select: userSelect } },
    orderBy: [{ createdAt: "desc" }, { id: "desc" }],
    skip: args.offset,
    take: args.limit,
  });
  const liked = await checkLikeStatus(
    args.viewerId,
    EntityType.USER_POST,
    rows.map((row) => row.id)
  );
  return rows.map((row) => ({
    createdAt: row.createdAt,
    id: row.id,
    item: toHomeFeedItem(row, liked[row.id] || false),
  }));
}

export function toHomeFeedItem(post: UserPostRow, hasLiked: boolean) {
  // Direct posts stay postcard-only: no trip map/route journey or thread reel.
  // Optional place still shows as a single pin chip on the postcard card.
  const mapPins =
    post.latitude != null && post.longitude != null
      ? [
          {
            lat: post.latitude,
            lng: post.longitude,
            name: post.locationName,
          },
        ]
      : undefined;

  return {
    id: post.id,
    tripId: null as string | null,
    userId: post.userId,
    summaryText: post.caption,
    curatedMedia: post.media,
    caption: post.caption,
    coverMediaUrl: post.media[0] ?? null,
    templateChoice: "postcard" as const,
    generationStatus: "PUBLISHED" as const,
    isPublished: post.isPublished,
    publishedAt: post.publishedAt ? post.publishedAt.toISOString() : null,
    createdAt: post.createdAt.toISOString(),
    updatedAt: post.updatedAt.toISOString(),
    likeCount: post.likeCount,
    commentCount: post.commentCount,
    shareCount: post.shareCount,
    hasLiked,
    postKind: "direct" as const,
    locationName: post.locationName,
    latitude: post.latitude,
    longitude: post.longitude,
    placeId: post.placeId,
    threadPreview: [],
    mapPins,
    user: post.user
      ? {
          ...post.user,
          username: post.user.username ?? undefined,
          name: post.user.name ?? undefined,
          avatarUrl: post.user.avatarUrl ?? undefined,
          bio: post.user.bio ?? undefined,
          createdAt: post.user.createdAt.toISOString(),
          updatedAt: post.user.updatedAt.toISOString(),
        }
      : undefined,
    trip: null,
  };
}

async function normalize(
  db: PrismaTransactionClient | typeof prisma,
  userId: string,
  input: DirectPostInput
) {
  const caption = input.caption?.trim() ?? "";
  if (!caption) throw new ValidationError("Write a caption before posting");
  if (caption.length > CAPTION_MAX) {
    throw new ValidationError(
      `Caption must be less than ${CAPTION_MAX} characters`
    );
  }

  const media = await assertAuthorUploads(db, userId, input.media ?? []);
  if (media.length > MAX_POST_MEDIA) {
    throw new ValidationError(`You can choose up to ${MAX_POST_MEDIA} photos`);
  }

  const locationName = input.locationName?.trim() || null;
  if (locationName && locationName.length > LOCATION_MAX) {
    throw new ValidationError("Location name is too long");
  }

  const latitude = input.latitude ?? null;
  const longitude = input.longitude ?? null;
  if ((latitude == null) !== (longitude == null)) {
    throw new ValidationError("A location needs both latitude and longitude");
  }
  if (
    latitude != null &&
    longitude != null &&
    (latitude < -90 ||
      latitude > 90 ||
      longitude < -180 ||
      longitude > 180)
  ) {
    throw new ValidationError("That location is outside the map");
  }

  let placeId: string | null = input.placeId ?? null;
  if (placeId) {
    const place = await db.place.findUnique({
      where: { id: placeId },
      select: { id: true },
    });
    if (!place) throw new ValidationError("That place was not found");
  } else {
    placeId = null;
  }

  return {
    caption,
    media,
    locationName,
    latitude,
    longitude,
    placeId,
    templateChoice: "postcard" as const,
  };
}

async function deleteEngagement(
  tx: PrismaTransactionClient,
  postId: string
) {
  const postEntity = EntityType.USER_POST;
  for (;;) {
    const candidates = await tx.comment.findMany({
      where: { entityType: postEntity, entityId: postId },
      select: { id: true, _count: { select: { replies: true } } },
    });
    const leaves = candidates.filter((comment) => comment._count.replies === 0);
    if (leaves.length === 0) break;
    const ids = leaves.map((comment) => comment.id);
    await tx.like.deleteMany({
      where: { entityType: EntityType.COMMENT, entityId: { in: ids } },
    });
    await tx.comment.deleteMany({ where: { id: { in: ids } } });
  }
  await tx.like.deleteMany({
    where: { entityType: postEntity, entityId: postId },
  });
  await tx.share.deleteMany({
    where: { entityType: postEntity, entityId: postId },
  });
  await tx.notification.deleteMany({
    where: { entityType: postEntity, entityId: postId },
  });
}
