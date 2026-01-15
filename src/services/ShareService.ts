// src/services/ShareService.ts

import { EntityType, ShareType } from "@prisma/client";
import { nanoid } from "nanoid";
import { prisma } from "@/lib/prisma";

export class ShareService {
  static async createShare(
    userId: string,
    entityType: EntityType,
    entityId: string,
    shareType: ShareType,
    metadata: any,
    expiresAt?: Date
  ) {
    const shareToken = nanoid(16);
    return await prisma.$transaction(async (tx) => {
      const share = await tx.share.create({
        data: {
          userId,
          entityType,
          entityId,
          shareToken,
          shareType,
          metadata,
          expiresAt,
        },
      });
      if (entityType === "TRIP_FINAL_POST") {
        await tx.tripFinalPost.update({
          where: { id: entityId },
          data: { shareCount: { increment: 1 } },
        });
      }
      return share;
    });
  }
}
