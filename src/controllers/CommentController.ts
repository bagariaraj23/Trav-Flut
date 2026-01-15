// src/controllers/CommentController.ts

import { Request, Response } from "express";
import { EntityType } from "@prisma/client";
import { sanitizeInput } from "../lib/security";
import { prisma } from "@/lib/prisma";

export class CommentController {
  static async postComment(req: Request, res: Response) {
    const { entityType, entityId, contentText, parentCommentId } = req.body;
    if (!req.user) return res.status(401).json({ error: "Unauthorized" });
    const userId = req.user.id;
    if (!Object.values(EntityType).includes(entityType))
      return res.status(400).json({ error: "Invalid entityType" });
    if (!contentText || contentText.length > 250)
      return res.status(400).json({ error: "Comment too long" });
    const sanitizedText = sanitizeInput(contentText);
    const comment = await prisma.$transaction(async (tx) => {
      const newComment = await tx.comment.create({
        data: {
          userId,
          entityType,
          entityId,
          contentText: sanitizedText,
          parentCommentId,
        },
      });
      if (entityType === "TRIP_FINAL_POST") {
        await tx.tripFinalPost.update({
          where: { id: entityId },
          data: { commentCount: { increment: 1 } },
        });
      }
      if (entityType === "TRIP_THREAD_ENTRY") {
        await tx.tripThreadEntry.update({
          where: { id: entityId },
          data: { commentCount: { increment: 1 } },
        });
      }
      return newComment;
    });
    res.json({ success: true, data: comment });
  }

  static async deleteComment(req: Request, res: Response) {
    const { id } = req.params;
    if (!req.user) return res.status(401).json({ error: "Unauthorized" });
    const userId = req.user.id;
    const comment = await prisma.comment.findUnique({ where: { id } });
    if (!comment || comment.userId !== userId)
      return res.status(403).json({ error: "Forbidden" });
    await prisma.$transaction(async (tx) => {
      await tx.comment.delete({ where: { id } });
      if (comment.entityType === "TRIP_FINAL_POST") {
        await tx.tripFinalPost.update({
          where: { id: comment.entityId },
          data: { commentCount: { decrement: 1 } },
        });
      }
      if (comment.entityType === "TRIP_THREAD_ENTRY") {
        await tx.tripThreadEntry.update({
          where: { id: comment.entityId },
          data: { commentCount: { decrement: 1 } },
        });
      }
    });
    res.json({ success: true });
  }
}
