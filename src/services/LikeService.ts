// src/services/LikeService.ts

import { PrismaClient, EntityType } from '@prisma/client'
const prisma = new PrismaClient()

export class LikeService {
  static async createLike(userId: string, entityType: EntityType, entityId: string) {
    return await prisma.$transaction(async (tx) => {
      const existing = await tx.like.findFirst({
        where: { userId, entityType, entityId }
      })
      if (existing) {
        return existing
      }
      const like = await tx.like.create({
        data: { userId, entityType, entityId }
      })
      if (entityType === 'TRIP_FINAL_POST') {
        await tx.tripFinalPost.update({
          where: { id: entityId },
          data: { likeCount: { increment: 1 } }
        })
      }
      if (entityType === 'TRIP_THREAD_ENTRY') {
        await tx.tripThreadEntry.update({
          where: { id: entityId },
          data: { likeCount: { increment: 1 } }
        })
      }
      return like
    })
  }

  static async deleteLike(userId: string, entityType: EntityType, entityId: string) {
    return await prisma.$transaction(async (tx) => {
      const like = await tx.like.findFirst({
        where: { userId, entityType, entityId }
      })
      if (!like) return null
      await tx.like.delete({
        where: { id: like.id }
      })
      if (entityType === 'TRIP_FINAL_POST') {
        await tx.tripFinalPost.update({
          where: { id: entityId },
          data: { likeCount: { decrement: 1 } }
        })
      }
      if (entityType === 'TRIP_THREAD_ENTRY') {
        await tx.tripThreadEntry.update({
          where: { id: entityId },
          data: { likeCount: { decrement: 1 } }
        })
      }
      return like
    })
  }
}